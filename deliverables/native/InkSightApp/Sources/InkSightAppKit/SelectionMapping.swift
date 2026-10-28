import Foundation
import CoreText
import CoreGraphics
import InkSightCore

// MARK: - SelectionMapping（FR-013 长按选句的坐标→字符映射）

/// 把触摸坐标映射到**字符偏移区间**（FR-013 长按选句）。
///
/// 原理（CoreText）：
/// - 每行由 `CoreTextLineCompositor` 生成等价 `CTLine`，行顶部 y 已知（`yTopPositions`）；
/// - 给定触摸点 → 找到所在行（y 比较）→ `CTLineGetStringIndexForPosition` 得**字符索引**；
/// - 选句口径：**词/句边界**——取所在行从行首到命中字符的区间为选中范围
///   （跨行选区与精确词边界属编辑器级能力，本期做"行级选句"并如实登记边界）。
///
/// 定位铁律：选区以 `charOffset + charLength` 表达（**无 pageIndex**）。
public enum SelectionMapping {

    /// 选句结果。
    public struct Selection: Equatable, Sendable {
        public let charOffset: Int
        public let charLength: Int
        public let selectedText: String

        public init(charOffset: Int, charLength: Int, selectedText: String) {
            self.charOffset = charOffset
            self.charLength = charLength
            self.selectedText = selectedText
        }
    }

    /// 行几何（用于命中测试）。
    public struct LineGeometry: Equatable, Sendable {
        /// 行顶 y（同 `yTopPositions` 口径）。
        public let yTop: CGFloat
        /// 行盒高（字号×行高倍数）。
        public let height: CGFloat
        /// 行首 x（左内边距）。
        public let leadingX: CGFloat

        public init(yTop: CGFloat, height: CGFloat, leadingX: CGFloat) {
            self.yTop = yTop
            self.height = height
            self.leadingX = leadingX
        }

        /// 点是否落在本行盒内（x 从 leadingX 起，y 在行盒内）。
        public func contains(_ point: CGPoint) -> Bool {
            point.y >= yTop && point.y < yTop + height
                && point.x >= leadingX
        }
    }

    /// 把点映射到所在行的选中区间。
    ///
    /// - Parameters:
    ///   - point: 触摸点（页面坐标系）。
    ///   - page: 当前页排版（提供行与字符区间）。
    ///   - chapterText: 整章文本（取选中文本用）。
    ///   - geometries: 每行几何（`yTopPositions` 对齐）。
    /// - Returns: 选中区间；点不在任何行内 → nil（诚实：不假装选中）。
    public static func selectLine(at point: CGPoint,
                                  page: TypesetPage,
                                  chapterText: String,
                                  geometries: [LineGeometry]) -> Selection? {
        guard let hitIndex = geometries.firstIndex(where: { $0.contains(point) }),
              hitIndex < page.lines.count else { return nil }

        let line = page.lines[hitIndex]
        let ns = chapterText as NSString
        let start = min(line.charOffset, ns.length)
        let length = min(line.charLength, ns.length - start)
        guard length > 0 else { return nil }

        // 行级选区：从行首到行尾（FR-013 的"选句"降级为"选行"，跨行/词边界待后续）
        let text = ns.substring(with: NSRange(location: start, length: length))
        return Selection(charOffset: start, charLength: length, selectedText: text)
    }

    /// 构造行几何数组（与 `CoreTextLineCompositor.yTopPositions` 对齐）。
    public static func geometries(for page: TypesetPage,
                                  typography: ReaderTypography) -> [LineGeometry] {
        let lineHeight = CGFloat(typography.lineHeight)
        var y = CGFloat(typography.insets.top)
        var result: [LineGeometry] = []
        for (i, line) in page.lines.enumerated() {
            if i > 0, line.isParagraphStart {
                y += CGFloat(typography.paragraphSpacingBefore)
            }
            result.append(LineGeometry(yTop: y, height: lineHeight,
                                       leadingX: CGFloat(typography.insets.leading)))
            y += lineHeight
        }
        return result
    }
}
