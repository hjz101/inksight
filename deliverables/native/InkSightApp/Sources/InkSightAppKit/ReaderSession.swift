import Foundation
import Combine
import InkSightCore

// MARK: - RepaginationOutcome（重排的可观测输出）

/// 重排结果（开发包 #8：换排版的可观测输出）。
///
/// 供 UI 直接呈现「用户可读反馈」，**视图层不另拼字面**（文案单一来源，同 `MotionSpec.chineseName` 的纪律）。
public struct RepaginationOutcome: Equatable, Sendable {

    /// 结果状态（三值，诚实语义——**不伪装成功**）。
    public enum Status: String, Equatable, Sendable {
        /// 已重排（签名变化 → 缓存作废 → 当前章同步重排）。
        case ok
        /// 排版未变（签名相同）→ 命中缓存，未重排。
        case unchanged
        /// **无正文**（诚实空态）：不重排、不落锚点、不产出「成功」表述。
        case noContent
    }

    /// 结果状态。
    public let status: Status
    /// 应用前的签名 digest（首次为 nil）。
    public let oldSignature: String?
    /// 应用后的签名 digest（无正文时为当前签名或空串）。
    public let newSignature: String
    /// 是否触发了缓存全作废（O(1) 世代号 +1）。
    public let cacheInvalidated: Bool
    /// 当前章同步重排耗时（毫秒）。
    public let currentChapterRetimeMs: Double
    /// 落点 charOffset——**重排前后不变**（定位铁律：只 charOffset，绝不 pageIndex）。
    public let landingCharOffset: Int
    /// 落点所在的新页索引（由 `charOffset` 经**新锚点**二分得到，**不是旧页码**）。
    public let landingPageIndex: Int
    /// 落点误差（字符数）：目标 charOffset 与新页页首 charOffset 之差。
    public let landingErrorChars: Int
    /// 新页覆盖的字符数（用于判定「误差 ≤1 屏」）。
    public let landingPageLength: Int
    /// 重排前的总页数。
    public let pageCountBefore: Int
    /// 重排后的总页数。
    public let pageCountAfter: Int
    /// 用户可读反馈（UI 直接呈现）。
    public let message: String

    public init(status: Status,
                oldSignature: String?,
                newSignature: String,
                cacheInvalidated: Bool,
                currentChapterRetimeMs: Double,
                landingCharOffset: Int,
                landingPageIndex: Int,
                landingErrorChars: Int,
                landingPageLength: Int,
                pageCountBefore: Int,
                pageCountAfter: Int,
                message: String) {
        self.status = status
        self.oldSignature = oldSignature
        self.newSignature = newSignature
        self.cacheInvalidated = cacheInvalidated
        self.currentChapterRetimeMs = currentChapterRetimeMs
        self.landingCharOffset = landingCharOffset
        self.landingPageIndex = landingPageIndex
        self.landingErrorChars = landingErrorChars
        self.landingPageLength = landingPageLength
        self.pageCountBefore = pageCountBefore
        self.pageCountAfter = pageCountAfter
        self.message = message
    }
}

// MARK: - ReaderSession（阅读会话：可换排版 ＋ 落点重定位）

/// 阅读会话（开发包 #8）：持有当前引擎与当前页，支持**换排版**与**落点重定位**。
///
/// **定位铁律（贯穿本类）**：
/// - 重排前后落点用**同一个 `charOffset`** 表达；新页索引由 `charOffset` 经**新锚点**二分得到；
/// - **绝不引入 `pageIndex` 依赖**——页码是派生量，改字号后必然漂移，落盘即埋雷；
/// - 进度持久化仍只 `charOffset + fingerprint`（`ReadingProgress` 4 字段，类型层保证无 pageIndex）。
///
/// **并发**：本类承载 SwiftUI 可观察状态，应在主线程使用；后台重分页走独立的
/// `RepaginationScheduler`（只碰 `PaginationCoordinator`，不碰本类）。
public final class ReaderSession: ObservableObject {

    /// 当前生效的引擎（换排版后被替换为新排版的引擎）。
    @Published public private(set) var engine: ReaderEngine?
    /// 当前页索引（换排版后按新锚点重新定位）。
    @Published public var currentPage: Int = 0
    /// 最近一次重排结果（用户可读反馈）。
    @Published public private(set) var lastOutcome: RepaginationOutcome?

    /// 分页协调器（持有 `PageAnchorCache` / `CTFrameCache` 与后台队列）。
    public let coordinator: PaginationCoordinator

    /// - Parameter coordinator: **默认即 App 级单例**（NFR-11：单例由**构造**保证，
    ///   不靠「记得传 `.shared`」——漏传即静默退化成第二个真相，且无任何测试能捕捉）。
    ///   需要隔离（如单测）时**显式**传独立实例。
    public init(engine: ReaderEngine?, coordinator: PaginationCoordinator = .shared) {
        self.engine = engine
        self.coordinator = coordinator
    }

    /// 落点 charOffset：优先取进度记录（跨会话恢复），否则取当前页页首。
    public var landingCharOffset: Int {
        if let progress = engine?.currentProgress() { return progress.charOffset }
        if let e = engine, let page = e.page(at: currentPage) { return page.anchor.charOffset }
        return 0
    }

    /// 采纳外部注入的引擎（换书／换章时替换）。
    ///
    /// **换排版后不会被旧引擎覆盖**：只在 `bookID`／`chapterID` 不同源时替换，
    /// 否则会把刚重排好的新引擎又换回旧排版（那正是开发包 #8 要修的缺口）。
    public func adopt(_ injected: ReaderEngine?) {
        guard let injected else { return }
        if let current = engine {
            guard current.bookID != injected.bookID || current.chapterID != injected.chapterID else { return }
        }
        engine = injected
        currentPage = injected.recoverPageIndex()
    }

    /// 恢复落点：按进度记录里的 `charOffset` 经锚点二分定位到页（定位铁律）。
    public func restoreLanding() {
        guard let engine else { return }
        currentPage = engine.recoverPageIndex()
    }

    /// 换排版（开发包 #8 主链路）：**同步重排当前章 → 落点按同一 `charOffset` 重新二分定位**。
    ///
    /// 判据：重排后落点应落在「同一 `charOffset` 所属的新页」上，误差 ≤1 屏
    /// （沿用 #3/#4/#5 的既有口径：误差 ≤ 新页覆盖的字符数）。
    ///
    /// 无正文时返回 `.noContent`——**诚实空态，不伪装成功**。
    /// - Parameters:
    ///   - containerSize: 容器尺寸——**默认取 `ReaderLayout.shared`（唯一来源）**，
    ///     不引入第二套尺寸常量（开发包 #10 容器尺寸贯通）。
    ///   - screenScale: 屏幕缩放——同上，取自 `ReaderLayout.shared`。
    @discardableResult
    public func applyTypography(_ typography: ReaderTypography,
                                containerSize: CGSize = ReaderLayout.shared.containerSize,
                                screenScale: Double = ReaderLayout.shared.screenScale,
                                kinsoku: Kinsoku = .v1) -> RepaginationOutcome {
        guard let engine, !engine.chapterText.isEmpty else {
            let outcome = RepaginationOutcome(
                status: .noContent,
                oldSignature: coordinator.currentSignature?.digest,
                newSignature: coordinator.currentSignature?.digest ?? "",
                cacheInvalidated: false,
                currentChapterRetimeMs: 0,
                landingCharOffset: 0,
                landingPageIndex: 0,
                landingErrorChars: 0,
                landingPageLength: 0,
                pageCountBefore: 0,
                pageCountAfter: 0,
                message: "无可重排内容：当前没有打开的书或章节正文。"
            )
            lastOutcome = outcome
            return outcome
        }

        // 落点（重排前取）：**同一个 charOffset**，重排后用它在新锚点上重新二分定位
        let targetOffset = landingCharOffset
        let pageCountBefore = engine.pageCount

        let report = coordinator.apply(typography,
                                       chapterText: engine.chapterText,
                                       chapterID: engine.chapterID,
                                       containerSize: containerSize,
                                       screenScale: screenScale,
                                       kinsoku: kinsoku)

        // 新引擎：同 bookID / 同 chapterID / 同正文 / 新排版；**共享同一份进度仓库**（进度不丢）
        let newEngine = ReaderEngine(bookID: engine.bookID,
                                     chapterID: engine.chapterID,
                                     chapterText: engine.chapterText,
                                     typography: typography,
                                     kinsoku: kinsoku,
                                     containerSize: containerSize,
                                     progressStore: engine.progressStore)

        // 新页索引：**由 charOffset 经新锚点二分得到**（不是旧页码）
        let newIndex = newEngine.resolvePageIndex(for: targetOffset)
        let newPageStart = newEngine.page(at: newIndex)?.anchor.charOffset ?? targetOffset
        let newPageLength = newEngine.page(at: newIndex)?.anchor.charLength ?? 0

        self.engine = newEngine
        self.currentPage = newIndex

        let errorChars = abs(targetOffset - newPageStart)
        let status: RepaginationOutcome.Status = report.cacheInvalidated ? .ok : .unchanged
        let message: String
        switch status {
        case .ok:
            message = "已重排：\(pageCountBefore) 页 → \(newEngine.pageCount) 页，"
                + String(format: "耗时 %.1f ms；", report.currentChapterRetimeMs)
                + "落点保持在第 \(newIndex + 1) 页（同一字符偏移）。"
        case .unchanged:
            message = "排版未变化，已复用现有分页（未重排）；当前第 \(newIndex + 1)/\(newEngine.pageCount) 页。"
        case .noContent:
            message = "无可重排内容。"
        }

        let outcome = RepaginationOutcome(
            status: status,
            oldSignature: report.oldSignature,
            newSignature: report.newSignature,
            cacheInvalidated: report.cacheInvalidated,
            currentChapterRetimeMs: report.currentChapterRetimeMs,
            landingCharOffset: targetOffset,
            landingPageIndex: newIndex,
            landingErrorChars: errorChars,
            landingPageLength: newPageLength,
            pageCountBefore: pageCountBefore,
            pageCountAfter: newEngine.pageCount,
            message: message
        )
        lastOutcome = outcome
        return outcome
    }
}
