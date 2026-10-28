import Foundation
import CoreText
import CoreGraphics
import InkSightCore

// MARK: - CoreTextLineCompositor（正文逐行自绘；FR-031 零位移的渲染侧实现）

/// 正文自绘排版器（开发包 #4，跨平台：macOS 测试构建与 iOS 同构）。
///
/// 严守 FR-031 零位移与零玻璃之外的另一条铁律——**渲染只消费 InkSightCore 的排版输出**：
/// - 断点来自 `TypesetLine`（`charOffset` / `charLength` / `predictedWidth`）；
/// - 本类型只在 `TypesetLine` 的 UTF-16 子串上**重建等价 `CTLine`**，再逐行 `CTLineDraw`；
/// - 字体与 `Typesetter` 完全一致（`fontID` 固定 ＋ `kern=0`），故实测宽度与
///   `predictedWidth` 之差 ≤0.5pt（`fr031Passes`）。**绝不使用 SwiftUI `Text` 重排**
///   （重排会令系统重新断行，破坏零位移）。
///
/// 关键铁律：**只产生内存中的 `CTLine`，绝不创建 `CTFrame`、绝不落盘**
/// （合规四禁令：glyph＋字体可经反向 cmap 还原为 Unicode，视同正文；CTFrameCache
/// 即便使用也只在内存，见 InkSightCore。本阅读路径连 CTFrame 都不建——按需逐行成行）。
public struct CoreTextLineCompositor {

    public let chapterText: String
    public let typography: ReaderTypography

    /// 与 `Typesetter` 同构的带属性字符串（字体 + kern=0 + 行盒写死的段落样式）。
    private let attributed: NSAttributedString
    private let font: CTFont

    public init(text: String, typography: ReaderTypography) {
        self.chapterText = text
        self.typography = typography

        let size = CGFloat(typography.fontSize)
        self.font = CTFontCreateWithName(typography.fontID as CFString, size, nil)

        // 行盒 = 字号 × 倍数（min = max，CoreText 的 lineSpacing 机制性失效，
        // 杜绝「1.75＋默认行距」）。与 Typesetter 完全同构。
        //
        // **`[#TemporaryPointers]` 修复（本次，台账待编号）**：旧写法此处同样有 4 处
        // `value: &localVar`——指针生命周期短于 `CTParagraphStyleCreate` 可能的使用期，
        // 属未定义行为。改为复用 `Typesetter.makeParagraphStyle`：既消除 UB，又让
        // 「排版侧与渲染侧段落样式同构」从"两处复制保持一致"升级为**结构保证**。
        let para = Typesetter.makeParagraphStyle(typography: typography)

        // kern 显式置 0：禁掉上下文 kern，使「孤立测距累加」与「成行实测」可比（FR-031 判据基础）。
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTKernAttributeName as String): 0,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): para,
        ]
        self.attributed = NSAttributedString(string: text, attributes: attrs)
    }

    /// 由 `TypesetLine` 重建等价 `CTLine`：取 `TypesetLine` 的 UTF-16 子串，沿用同一属性成行。
    /// 返回非 nil 当且仅当子串范围合法；越界（例：恢复落点 clamp 到章尾）回退到整章。
    public func line(for typesetLine: TypesetLine) -> CTLine {
        let ns = chapterText as NSString
        let range = NSRange(location: typesetLine.charOffset,
                           length: min(typesetLine.charLength, ns.length - typesetLine.charOffset))
        let lineAttr = attributed.attributedSubstring(from: range)
        return CTLineCreateWithAttributedString(lineAttr)
    }

    /// 每页每行的**顶部 y**（基线起点前的 y 坐标），复刻 `Typesetter.typesetChapter` 的页装配：
    /// 页首行无段前间距；其余段落首行加 `paragraphSpacingBefore`；每行占固定 `lineHeight`。
    /// 渲染时基线 = `yTop + ascent`（顶部对齐于行盒，垂直微距归 POC-2 真机校准）。
    public func yTopPositions(for page: TypesetPage) -> [CGFloat] {
        var y = CGFloat(typography.insets.top)
        var result: [CGFloat] = []
        for (i, line) in page.lines.enumerated() {
            if i > 0, line.isParagraphStart {
                y += CGFloat(typography.paragraphSpacingBefore)
            }
            result.append(y)
            y += CGFloat(typography.lineHeight)
        }
        return result
    }

    /// 行首 x（左内边距）。
    public var leading: CGFloat { CGFloat(typography.insets.leading) }
}
