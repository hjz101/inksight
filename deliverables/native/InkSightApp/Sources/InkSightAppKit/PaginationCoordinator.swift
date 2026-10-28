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

    private let lock = NSLock()
    /// 当前生效的排版签名（nil 表示尚未应用过）。`wouldInvalidate` 以此为基准。
    private var _currentSignature: TypographySignature?
    /// 后台待重分页章队列（`(id, text)`）。
    private var backgroundQueue: [(id: Int, text: String)] = []

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

    // MARK: - 后台分批重分页

    /// 入队其余章（后台分批）：返回入队后队列中**待处理章总数**（累积计数）。
    @discardableResult
    public func enqueueBackground(_ chapters: [(id: Int, text: String)]) -> Int {
        lock.lock(); defer { lock.unlock() }
        backgroundQueue.append(contentsOf: chapters)
        return backgroundQueue.count
    }

    /// 从队列弹出一章执行后台重分页（不触碰 UI 线程）。无待处理章返回 nil。
    ///
    /// 落库到 `PageAnchorCache`（按当前签名），供后续打开该章时命中。
    public func processOneBackgroundChapter(typography: ReaderTypography,
                                            containerSize: CGSize,
                                            screenScale: Double,
                                            kinsoku: Kinsoku = .v1) -> (id: Int, anchors: [PageAnchor])? {
        lock.lock()
        guard !backgroundQueue.isEmpty else { lock.unlock(); return nil }
        let (id, text) = backgroundQueue.removeFirst()
        lock.unlock()

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
