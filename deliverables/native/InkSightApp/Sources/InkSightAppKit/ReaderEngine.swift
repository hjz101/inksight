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
    /// 默认排版参数（**逐值对齐 PRD 正文样式基线**）。
    ///
    /// **D-99 修正（真实偏差）**：此前为 `fontSize: 18 / 段前 8 / 段后 8 / 缩进 28 /
    /// 比例 1.5`——**全部不符合 PRD 基线**，且字号 18 **不在 FR-009 的档位集
    /// {19, 20, 21}** 内（D-72 引入档位制时漏了这个收口点）。现按 PRD 修正：
    /// - 字号 **20**（档位默认，FR-009）；
    /// - 行高 **1.75**；
    /// - 段前 **12** / 段后 **0**（PRD：段间视觉间距 12pt，不由行盒余量叠加）；
    /// - 缩进 **0**（PRD：首行缩进默认 0，开启时 = 2×字号）；
    /// - 图片占位比例 **0.75**（3:4，FR-018-ac c 的默认值）；
    /// - 边距 20（屏宽 >375 默认）。
    public static let `default` = ReaderTypography(
        fontID: "PingFangSC-Regular",
        fontSize: 20,
        lineHeightMultiplier: 1.75,
        paragraphSpacingBefore: 12,
        paragraphSpacingAfter: 0,
        insets: ReaderInsets(top: 24, leading: 20, bottom: 28, trailing: 20),
        indent: 0,
        imagePlaceholderAspect: 0.75
    )
}
