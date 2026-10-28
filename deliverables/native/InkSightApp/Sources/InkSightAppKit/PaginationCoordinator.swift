import Foundation
import CoreText
import InkSightCore

// MARK: - 重分页报告

/// 重分页报告（机制链路可观测性）：一次 `apply` 的副作用与耗时快照。
public struct RePaginationReport: Equatable, Sendable {
    /// 应用前的签名 digest（首次为 nil）。
    public let oldSignature: String?
    /// 应用后的签名 digest。
    public let newSignature: String
    /// 是否触发了缓存全作废（签名变化 → `invalidateAll` O(1) 世代号 +1）。
    public let cacheInvalidated: Bool
    /// 当前章同步重排耗时（毫秒）。命中缓存（签名未变）时为 0——即「旧签名复用落空触发重算」的反面：
    /// 命中则不重排、不耗时。
    public let currentChapterRetimeMs: Double
    /// 本次 apply 时已在后台队列中待重分页的章数（其余章经 `enqueueBackground` 入队）。
    public let backgroundChaptersScheduled: Int

    public init(oldSignature: String?,
                newSignature: String,
                cacheInvalidated: Bool,
                currentChapterRetimeMs: Double,
                backgroundChaptersScheduled: Int) {
        self.oldSignature = oldSignature
        self.newSignature = newSignature
        self.cacheInvalidated = cacheInvalidated
        self.currentChapterRetimeMs = currentChapterRetimeMs
        self.backgroundChaptersScheduled = backgroundChaptersScheduled
    }
}

// MARK: - PaginationCoordinator（开发包 #6 · TypographySignature 缓存作废机制链路）

/// 分页协调器（开发包 #6）：打通「TypographySignature 变更 → 缓存作废 → 重分页」机制链路。
///
/// 机制链路（只读消费 InkSightCore 冻结契约，不改动）：
/// 1. 由新排版参数计算 `TypographySignature`；
/// 2. `wouldInvalidate` 纯函数比对 `currentSignature`（命中即作废）；
/// 3. 命中 → `PageAnchorCache.invalidateAll()` + `CTFrameCache.invalidateAll()`（**O(1) 世代号 +1**，不遍历不删除）；
/// 4. 当前章**同步重排**（`Typesetter.typesetChapter`）+ 落库 `PageAnchorCache`；
/// 5. 其余章经 `enqueueBackground` 入队，由 `processOneBackgroundChapter` 后台分批重分页。
///
/// **约束调和（FR-031 第 19 行 vs NFR-08 第 31 行，两者并存）**：
/// - FR-031 授权「其余章后台分批（**1 章/次**）」重分页；
/// - NFR-08 禁止「遍历全书生成 anchor」的代码，并限定「预取仅内存 ≤3 章」。
/// 二者靠两条实现纪律同时成立：**① 每批只处理 1 章**（`processOneBackgroundChapter` 单章出队）；
/// **② 队列不持正文**（只存取正文的闭包，处理时才切片读取、读完即释放）。
/// 若队列直接持有全书正文（`[(id, text: String)]` 全量入队），则正文全量常驻内存，
/// 等价于把「遍历全书」搬进内存，同时破 NFR-08 与 NFR-03——**故本类提供 `enqueueBackgroundLazy` 为生产路径**。
///
/// 严守铁律：
/// - `CTFrameCache` **仅内存**，严禁落盘（合规四禁令：glyph＋字体可经反向 cmap 还原为 Unicode 视同正文）；
///   本协调器不写任何磁盘路径，只调 `invalidateAll` 释放。
/// - 进度只 `charOffset + fingerprint`（本协调器不触碰进度存储）。
/// - 0 玻璃（数据层，不涉及 SwiftUI）。
/// - `InkSightCore` 7 个源文件冻结，**只读消费**：不修改 `Typesetter` / `PageAnchorCache` / `CTFrameCache`
///   / `TypographySignature` / `Kinsoku` / `ChapterScanner` / `StyleStripper`。
public final class PaginationCoordinator: @unchecked Sendable {

    public let pageAnchorCache: PageAnchorCache
    public let ctFrameCache: CTFrameCache

    /// **App 级单例**（开发包 #8）。
    ///
    /// 理由：`TypographySignature` 全局可比，但 `PageAnchorCache` / `CTFrameCache` 挂在
    /// **协调器实例**上——两个实例＝两套缓存＝同一本书在设置页与阅读器各排一遍，
    /// 缓存互不命中（白排一遍），且 NFR-03 的内存预算按实例翻倍。
    /// 故运行时**必须共用同一实例**（设置页与阅读器）。
    ///
    /// 测试请用**独立实例**（`PaginationCoordinator()`），避免跨用例污染。
    public static let shared = PaginationCoordinator()

    private let lock = NSLock()
    /// 当前生效的排版签名（nil 表示尚未应用过）。`wouldInvalidate` 以此为基准。
    private var _currentSignature: TypographySignature?
    /// 后台待重分页章队列（`(id, textProvider)`）。
    ///
    /// **队列只存「取正文的闭包」，不存正文本身**——这是本包暴露出的新约束点（见 D-52 新增条目）：
    /// 若队列直接持有全书正文，等于把「遍历全书生成 anchor」搬进了内存（正文全量常驻），
    /// 同时破 NFR-08（任何遍历全书生成 anchor 的代码视为违规）与 NFR-03（会话正文本 ≤50KB／≤3 章）。
    /// 取正文改为**按需闭包**：处理哪一章才切片读哪一章（复用 #5 `BookShelfStore.chapterText(for:)`），
    /// 处理完即释放，任意时刻常驻正文 ≤1 章。
    private var backgroundQueue: [(id: Int, textProvider: () -> String?)] = []

    public init(pageAnchorCache: PageAnchorCache = PageAnchorCache(),
                ctFrameCache: CTFrameCache = CTFrameCache()) {
        self.pageAnchorCache = pageAnchorCache
        self.ctFrameCache = ctFrameCache
    }

    // MARK: - 当前签名（带锁读，符合 @unchecked Sendable）

    /// 当前生效的排版签名（只读）。
    public var currentSignature: TypographySignature? {
        lock.lock(); defer { lock.unlock() }
        return _currentSignature
    }

    private func setCurrentSignature(_ sig: TypographySignature?) {
        lock.lock(); defer { lock.unlock() }
        _currentSignature = sig
    }

    // MARK: - 纯函数：是否会使缓存作废

    /// 给定新签名，是否会使缓存作废：旧签名为 nil（首次）或 digest 不同即作废。
    ///
    /// 纯函数——不读缓存、不改状态，便于单测与推理。
    public func wouldInvalidate(_ new: TypographySignature) -> Bool {
        guard let current = currentSignature else { return true }
        return current.digest != new.digest
    }

    // MARK: - 应用新排版参数（机制链路主入口）

    /// 应用新的排版参数：返回一次重分页报告。
    ///
    /// - 签名变化 → `invalidateAll()`（O(1)）+ 当前章同步重排 + 落库；
    /// - 签名未变 → 命中缓存，**不重排、不落库、不耗重排时间**（返回 `currentChapterRetimeMs == 0`），
    ///   印证缓存价值（"旧签名复用落空触发重算"的反面：命中则跳过）。
    public func apply(_ typography: ReaderTypography,
                     chapterText: String,
                     chapterID: Int,
                     containerSize: CGSize,
                     screenScale: Double,
                     kinsoku: Kinsoku = .v1) -> RePaginationReport {
        let newSig = TypographySignature(typography: typography,
                                         containerSize: containerSize,
                                         screenScale: screenScale,
                                         kinsokuVersion: kinsoku.version)
        let old = currentSignature?.digest
        let invalidated = wouldInvalidate(newSig)

        if invalidated {
            // O(1) 全作废：世代号 +1，旧条目失配（不遍历不删除）
            pageAnchorCache.invalidateAll()
            // CTFrameCache 仅内存释放（合规禁令第 4 条：切书/签名变化即清空）
            ctFrameCache.invalidateAll()
            setCurrentSignature(newSig)

            // 当前章同步重排
            let start = DispatchTime.now()
            let result = typeset(chapterText: chapterText, chapterID: chapterID,
                                 typography: typography, containerSize: containerSize, kinsoku: kinsoku)
            let retimeMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            // 落库当前章锚点（新世代）
            pageAnchorCache.store(result.pages.map { $0.anchor }, for: chapterID, signatureHash: newSig.digest)

            let pending = lockAndCountQueue()
            return RePaginationReport(oldSignature: old,
                                      newSignature: newSig.digest,
                                      cacheInvalidated: true,
                                      currentChapterRetimeMs: retimeMs,
                                      backgroundChaptersScheduled: pending)
        } else {
            // 命中缓存：不重排、不落库、不耗重排时间
            let pending = lockAndCountQueue()
            return RePaginationReport(oldSignature: old,
                                      newSignature: newSig.digest,
                                      cacheInvalidated: false,
                                      currentChapterRetimeMs: 0,
                                      backgroundChaptersScheduled: pending)
        }
    }

    // MARK: - 会话结束 / 切书：释放全部内存页（合规禁令第 4 条）

    /// **合规禁令第 4 条的落地入口**：切书或阅读会话结束时调用，释放全部内存页缓存。
    ///
    /// 修复的历史缺口（台账待编号）：`CTFrame` 四禁令写着「切书或会话结束即释放」，
    /// 但此前 `invalidateAll()` **只在签名变化时**被调用——切书、退出阅读器都没有调用方，
    /// 即「释放」这条禁令在代码里从未被执行过。本方法把它变成可调用、可测量的显式动作。
    ///
    /// 释放范围：
    /// - `CTFrameCache.invalidateAll()`——CTFrame 视同正文，必须清（本方法的主目的）；
    /// - `PageAnchorCache.invalidateAll()`——锚点是派生量，本可保留，但切书后旧章的锚点
    ///   已无复用价值，且留着会占 NFR-03 的内存预算，故一并释放；
    /// - 后台队列清空——旧书的待重排章不得在新会话里继续跑。
    ///
    /// - Parameter clearingSignature: 是否同时清掉当前签名。
    ///   切书＝true（新书需重新 apply）；仅退出阅读器而保留书架上下文＝false。
    public func releaseSession(clearingSignature: Bool = true) {
        pageAnchorCache.invalidateAll()
        ctFrameCache.invalidateAll()
        lock.lock()
        backgroundQueue.removeAll()
        if clearingSignature { _currentSignature = nil }
        lock.unlock()
    }

    // MARK: - 后台分批重分页（1 章/次；正文按需取用）

    /// 入队其余章（后台分批重分页）：返回入队后队列中**待处理章总数**（累积计数）。
    ///
    /// **便捷入口（正文已在调用方内存）**：调用方已持有正文时可直接用本入口。
    /// ⚠️ 记忆体纪律：正文随闭包一起被队列持有，故**仅适用于正文本已在内存的短时场景
    /// （≤3 章，对齐 NFR-08「预取仅内存 ≤3 章」）**；生产路径（书架真实章节）请用
    /// `enqueueBackgroundLazy(_:)`，其正文按需切片读取、不常驻内存。
    @discardableResult
    public func enqueueBackground(_ chapters: [(id: Int, text: String)]) -> Int {
        // 注意：内层闭包显式捕获外部变量——内层 `$0` 会遮蔽外层 `$0`（编译期不可推断）
        enqueueBackgroundLazy(chapters.map { chapter in
            let text = chapter.text
            return (id: chapter.id, textProvider: { () -> String? in text })
        })
    }

    /// 入队其余章（**正文按需取用**，生产路径）：队列只存取正文的闭包，不存正文。
    ///
    /// 入队时**不读取正文**；只有真正处理到某章时才调用闭包取正文，取完即释放。
    /// 任意时刻常驻正文 ≤1 章（NFR-03「会话正文本 ≤50KB／≤3 章」的上限内）。
    ///
    /// 返回入队后队列中待处理章总数（累积计数）。
    @discardableResult
    public func enqueueBackgroundLazy(_ chapters: [(id: Int, textProvider: () -> String?)]) -> Int {
        lock.lock(); defer { lock.unlock() }
        backgroundQueue.append(contentsOf: chapters)
        return backgroundQueue.count
    }

    /// 从队列弹出一章执行后台重分页（**1 章/次**，对齐 FR-031「其余章后台分批（1 章/次）」）。
    ///
    /// 落库到 `PageAnchorCache`（按当前签名），供后续打开该章时命中。
    /// 若该章正文取不到（源文件被移除等），跳过并继续下一章。
    public func processOneBackgroundChapter(typography: ReaderTypography,
                                            containerSize: CGSize,
                                            screenScale: Double,
                                            kinsoku: Kinsoku = .v1) -> (id: Int, anchors: [PageAnchor])? {
        while true {
            lock.lock()
            guard !backgroundQueue.isEmpty else { lock.unlock(); return nil }
            let (id, provider) = backgroundQueue.removeFirst()
            lock.unlock()

            // 正文按需取用：此刻才读，读完即释放（不与全书正文同时常驻）
            guard let text = provider(), !text.isEmpty else { continue }

            let sig = TypographySignature(typography: typography,
                                          containerSize: containerSize,
                                          screenScale: screenScale,
                                          kinsokuVersion: kinsoku.version)
            let result = typeset(chapterText: text, chapterID: id,
                                 typography: typography, containerSize: containerSize, kinsoku: kinsoku)
            let anchors = result.pages.map { $0.anchor }
            pageAnchorCache.store(anchors, for: id, signatureHash: sig.digest)
            return (id: id, anchors: anchors)
        }
    }

    // MARK: - 内部

    private func lockAndCountQueue() -> Int {
        lock.lock(); defer { lock.unlock() }
        return backgroundQueue.count
    }

    /// 只读消费 `Typesetter`：自绘断点 → 行 → 页 → PageAnchor（不修改冻结契约）。
    private func typeset(chapterText: String,
                         chapterID: Int,
                         typography: ReaderTypography,
                         containerSize: CGSize,
                         kinsoku: Kinsoku) -> TypesetResult {
        let ts = Typesetter(text: chapterText, typography: typography,
                           containerSize: containerSize, kinsoku: kinsoku)
        return ts.typesetChapter(chapterID: chapterID)
    }
}
