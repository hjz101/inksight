import Foundation
import InkSightCore

// MARK: - RepaginationScheduler（后台重分页调度器）

/// 后台重分页调度器（开发包 #8）：**真实驱动** `PaginationCoordinator` 的后台队列。
///
/// 纪律（对齐 NFR-09 / NFR-08 / NFR-04，**不得回退**）：
/// - **① 每批只处理 1 章**：单章出队 → 单章重排 → 单章落锚点；
/// - **② 正文按需取、读完即释放**：队列只存取正文的闭包，不存正文——**常驻正文 ≤1 章**；
/// - **③ 可取消**：`cancel()` 后立即停止处理下一章（已在处理的那一章跑完即止），
///   对齐 NFR-04「`scenePhase != .active` 立即 `cancelAllTasks()`」的纪律精神；
/// - **④ 不一次性遍历全书**：调度是**增量、可中断**的，不是「先把全书正文装进内存再逐章分页」
///   （后者才是 NFR-08 禁止的那种遍历）。入队阶段只登记**取正文的闭包**，不读任何正文。
///
/// 线程：调度循环跑在 `Task.detached(priority: .utility)`，**不占主线程**；
/// 正文排版在后台线程完成（CoreText 排版线程安全）。
public final class RepaginationScheduler: @unchecked Sendable {

    /// 调度状态（用户可读反馈用）。
    public enum State: String, Equatable, Sendable {
        case idle        // 未开始
        case running     // 进行中
        case completed   // 已完成（队列处理完）
        case cancelled   // 已取消
    }

    /// 分页协调器（持有 `PageAnchorCache` / `CTFrameCache` 与后台队列）。
    public let coordinator: PaginationCoordinator

    /// 批次间隔（让出线程，使取消能及时生效；测试可调小）。
    public let batchDelay: Duration

    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var cancelled = false
    private var processedCount = 0
    private var totalCount = 0
    private var _state: State = .idle

    /// - Parameter coordinator: **默认即 App 级单例**（NFR-11：单例由**构造**保证，
    ///   不靠「记得传 `.shared`」）。需要隔离（如单测）时**显式**传独立实例。
    public init(coordinator: PaginationCoordinator = .shared,
                batchDelay: Duration = .milliseconds(0)) {
        self.coordinator = coordinator
        self.batchDelay = batchDelay
    }

    // MARK: - 可观测状态

    /// 当前状态。
    public var state: State { withLock { _state } }

    /// 已处理章数。
    public var processedChapterCount: Int { withLock { processedCount } }

    /// 本次调度总章数。
    public var totalChapterCount: Int { withLock { totalCount } }

    /// 是否仍在运行。
    public var isRunning: Bool { state == .running }

    /// 是否已被取消。
    public var isCancelled: Bool { withLock { cancelled } }

    // MARK: - 启动 / 取消

    /// 入队并启动后台调度。
    ///
    /// - Parameters:
    ///   - chapters: 待重排章；**只提供取正文的闭包**，正文不在入队时物化（纪律 ②）。
    ///   - maxChapters: 可选上限（限制本次调度覆盖的章数，nil ＝ 不限）。
    ///
    /// 进度反馈：本类**不持回调**（后台线程回调会与 UI 的 actor 隔离打架）。
    /// 调用方按需轮询 `processedChapterCount` / `state` 呈现状态。
    @discardableResult
    public func start(chapters: [(id: Int, textProvider: () -> String?)],
                      typography: ReaderTypography,
                      containerSize: CGSize,
                      screenScale: Double,
                      kinsoku: Kinsoku = .v1,
                      maxChapters: Int? = nil) -> Int {
        // 重新开始前先取消上一次（纪律 ③）
        cancel()

        let providers = maxChapters.map { Array(chapters.prefix($0)) } ?? chapters
        // 入队：只登记闭包，**不读任何正文**（纪律 ② / ④）
        coordinator.enqueueBackgroundLazy(providers)

        withLock {
            cancelled = false
            processedCount = 0
            totalCount = providers.count
            _state = .running
        }

        let loop = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.runLoop(typography: typography,
                               containerSize: containerSize,
                               screenScale: screenScale,
                               kinsoku: kinsoku)
        }
        withLock { task = loop }
        return providers.count
    }

    /// 取消调度：**立即停止处理下一章**（已在处理的那一章跑完即止）。
    ///
    /// 场景：用户切走、`scenePhase != .active`、切书、会话结束。
    public func cancel() {
        let running: Task<Void, Never>? = withLock {
            cancelled = true
            let t = task
            task = nil
            if _state == .running { _state = .cancelled }
            return t
        }
        running?.cancel()
    }

    // MARK: - 单批推进（后台循环与确定性测试共用同一条路径）

    /// 推进一批（＝**处理 1 章**）。返回是否真的处理了一章。
    ///
    /// 已取消或队列为空 → `false`（不再处理）。
    /// 测试可直接调用本方法驱动，**不依赖真实时钟**，与后台循环走完全相同的处理路径。
    @discardableResult
    public func processNextBatch(typography: ReaderTypography,
                                 containerSize: CGSize,
                                 screenScale: Double,
                                 kinsoku: Kinsoku = .v1) -> Bool {
        if withLock({ cancelled }) { return false }

        guard coordinator.processOneBackgroundChapter(typography: typography,
                                                     containerSize: containerSize,
                                                     screenScale: screenScale,
                                                     kinsoku: kinsoku) != nil else {
            return false
        }
        withLock { processedCount += 1 }
        return true
    }

    /// 后台循环（每批 1 章，批间让出线程使取消及时生效）。
    private func runLoop(typography: ReaderTypography,
                         containerSize: CGSize,
                         screenScale: Double,
                         kinsoku: Kinsoku) async {
        while !Task.isCancelled {
            let progressed = processNextBatch(typography: typography,
                                              containerSize: containerSize,
                                              screenScale: screenScale,
                                              kinsoku: kinsoku)
            if !progressed { break }
            if batchDelay > Duration.zero {
                try? await Task.sleep(for: batchDelay)
            }
        }
        withLock {
            if cancelled {
                _state = .cancelled
            } else {
                _state = .completed
            }
            task = nil
        }
    }

    // MARK: - 锁辅助

    /// 同步加锁helper（`NSLock.lock()` 不可在 async 上下文直接调用，故统一走本方法）。
    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
