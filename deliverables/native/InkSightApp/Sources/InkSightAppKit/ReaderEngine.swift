import Foundation
import InkSightCore

// MARK: - ReaderEngine（阅读器逻辑层；不触碰 InkSightCore 契约）

/// 阅读引擎（开发包 #4 逻辑层）：封装 InkSightCore 的 `Typesetter` 排版输出，提供
/// 分页、进度恢复（二分定位）、进度回写。
///
/// 严守铁律：
/// - **只消费** InkSightCore 的 `Typesetter.typesetChapter` 输出（`TypesetPage`/`TypesetLine`），
///   不修改冻结契约；
/// - 渲染坐标来自 `TypesetLine.predictedWidth` 累积（自绘，不依赖系统重排）→ 零位移；
/// - 进度持久化只 `charOffset + fingerprint`（复用 #3 的 `ReadingProgressStore`），
///   **绝不存 pageIndex**。
public final class ReaderEngine: @unchecked Sendable {

    public let bookID: String
    public let chapterID: Int
    public let chapterText: String
    public let typography: ReaderTypography
    public let typeset: TypesetResult

    /// 本次排版所用的**容器尺寸**（进 `TypographySignature`）。
    ///
    /// 开发包 #10：阅读器实测尺寸后若与本值不同，说明排版已过期，必须走重排链路
    /// （不静默沿用旧排版）；两端尺寸来源统一见 `ReaderLayout`。
    public let containerSize: CGSize

    /// 进度仓库（开发包 #8：换排版时**共享同一份**——重排后进度不丢）。
    ///
    /// 公开原因：换排版会新建引擎，必须复用同一份进度仓库，否则续读落点会丢。
    /// 仓库内仍只存 `charOffset + fingerprint`（4 字段，无 pageIndex）。
    public let progressStore: ReadingProgressStore

    public static let defaultContainerSize = CGSize(width: 360, height: 720)

    public init(bookID: String, chapterID: Int, chapterText: String,
                typography: ReaderTypography = .default,
                kinsoku: Kinsoku = .v1,
                containerSize: CGSize = ReaderEngine.defaultContainerSize,
                progressStore: ReadingProgressStore = ReadingProgressStore()) {
        self.bookID = bookID
        self.chapterID = chapterID
        self.chapterText = chapterText
        self.typography = typography
        self.containerSize = containerSize
        self.progressStore = progressStore
        let typesetter = Typesetter(text: chapterText, typography: typography,
                                    containerSize: containerSize, kinsoku: kinsoku)
        self.typeset = typesetter.typesetChapter(chapterID: chapterID)
    }

    /// 便捷初始化（开发包 #5）：仅给章节纯文本即可排版渲染，**替代/并存 #4 的 SampleChapter 注入路径**。
    /// `bookID` 由正文稳定哈希派生（会话内同一文本进度可恢复）；`chapterID` 默认 0。
    /// 导入真实文件时仍建议用全参 `init(bookID:chapterID:chapterText:)` 以绑定真实 bookID。
    public convenience init(chapterText: String,
                            typography: ReaderTypography = .default,
                            containerSize: CGSize = ReaderEngine.defaultContainerSize,
                            kinsoku: Kinsoku = .v1) {
        self.init(bookID: ReaderEngine.deriveBookID(from: chapterText),
                  chapterID: 0,
                  chapterText: chapterText,
                  typography: typography,
                  kinsoku: kinsoku,
                  containerSize: containerSize)
    }

    /// 由正文稳定派生 bookID（FNV-1a 64，InkSightCore 同源）。
    private static func deriveBookID(from text: String) -> String {
        let h = Fingerprint.fnv1a64(text)
        return "adhoc-\(String(format: "%016llx", h))"
    }

    public var pageCount: Int { typeset.pages.count }

    public var pages: [TypesetPage] { typeset.pages }

    public func page(at index: Int) -> TypesetPage? {
        guard index >= 0, index < typeset.pages.count else { return nil }
        return typeset.pages[index]
    }

    /// 由 `charOffset` 经 `PageAnchor` 二分定位所属页（定位铁律：只用 charOffset＋fingerprint）。
    public func resolvePageIndex(for charOffset: Int) -> Int {
        let anchors = typeset.pages.map { $0.anchor }
        if let found = anchors.pageContaining(charOffset: charOffset),
           let idx = typeset.pages.firstIndex(where: { $0.anchor.charOffset == found.charOffset }) {
            return idx
        }
        return max(0, typeset.pages.count - 1)   // 越界 → 末页（恢复三分支的 clamp）
    }

    /// 落点 `charOffset`（页首），用于恢复误差判定（应 ≤1 屏）。
    public func landingCharOffset(for charOffset: Int) -> Int {
        typeset.pages[resolvePageIndex(for: charOffset)].anchor.charOffset
    }

    /// 回写进度：**只存 charOffset＋fingerprint**，绝不 pageIndex。
    public func recordProgress(at charOffset: Int) {
        let idx = resolvePageIndex(for: charOffset)
        let fp = typeset.pages[idx].anchor.fingerprint
        progressStore.record(ReadingProgress(bookID: bookID, chapterID: chapterID,
                                            charOffset: charOffset, fingerprint: fp))
    }

    public func currentProgress() -> ReadingProgress? {
        progressStore.progress(for: bookID)
    }

    /// 进入阅读器时的进度恢复入口：**只取 charOffset**，经二分定位返回应停留的页码。
    /// 定位铁律：只依赖 charOffset＋fingerprint，绝不依赖 pageIndex。
    /// 无进度记录时回退章首（第 0 页）。
    public func recoverPageIndex() -> Int {
        guard let progress = currentProgress() else { return 0 }
        return resolvePageIndex(for: progress.charOffset)
    }

    /// 恢复落点的「页首 charOffset」（恢复误差判据：应 ≤1 屏 = 当前页范围内）。
    public func recoverLandingCharOffset() -> Int {
        guard let progress = currentProgress() else { return 0 }
        return landingCharOffset(for: progress.charOffset)
    }
}

// MARK: - ReaderTypography 默认排版（单一来源；InkSightCore 契约不动）

extension ReaderTypography {
    /// 骨架期默认排版参数（与 InkSightCore `ReaderTypography` 同源；值按 PRD/架构基线）。
    public static let `default` = ReaderTypography(
        fontID: "PingFangSC-Regular",
        fontSize: 18,
        lineHeightMultiplier: 1.75,
        paragraphSpacingBefore: 8,
        paragraphSpacingAfter: 8,
        insets: ReaderInsets(top: 24, leading: 20, bottom: 24, trailing: 20),
        indent: 28,
        imagePlaceholderAspect: 1.5
    )
}
