import Foundation
import CoreGraphics
import InkSightCore

// MARK: - ImagePlaceholderLayout（FR-018-ac c：图片占位的几何计算）

/// 图片占位的几何计算（渲染层用）。
///
/// 规格（PRD §3 排版表 + FR-018-ac c）：
/// - 图片**宽 ＝ 正文宽**（`containerWidth - leading - trailing`）；
/// - **占位比例 `imagePlaceholderAspect` 默认 3:4**（高/宽 = 1/0.75 = 1.333）；
/// - **aspect-fill**（长图会被裁，点击进全屏原图——本期只画占位，点击行为待真机）；
/// - 图与段间 **16pt**；
/// - **不得"源给了尺寸就用源的"**（比例恒由 `imagePlaceholderAspect` 决定）。
///
/// 为什么放在渲染层而不是排版层：`TypesetLine` 是**冻结契约**（按行字符区间），
/// 而图片块高度是行高的数倍。若在排版层插入"图片行"，会改变 `charOffset` 的语义，
/// 波及定位铁律、`PageAnchor`、`TypographySignature` —— 代价远大于收益。
/// 故渲染层做法：**占位标记所在行照常排版占一行高度，绘制时把该行区域替换成图片块**
/// （视觉上图片块会跨过下方若干行的位置，但那些行本来就是空的——
/// 因为占位标记是独占一段的，段后自然留白）。
public enum ImagePlaceholderLayout {

    /// 图与段间距（PRD：16pt）。
    public static let paragraphSpacing: CGFloat = 16

    /// 占位块尺寸。
    ///
    /// - Parameters:
    ///   - contentWidth: 正文宽（容器宽 − 左右边距）。
    ///   - aspect: `ReaderTypography.imagePlaceholderAspect`（宽/高比，默认 0.75 = 3:4）。
    /// - Returns: 占位块尺寸（**宽恒 = contentWidth**，高由比例算出）。
    public static func placeholderSize(contentWidth: CGFloat,
                                       aspect: Double) -> CGSize {
        let w = max(contentWidth, 0)
        // aspect 是"宽/高"（3:4 → 0.75），故 高 = 宽 / aspect
        let safeAspect = aspect > 0.01 ? aspect : 0.75
        let h = w / CGFloat(safeAspect)
        return CGSize(width: w, height: h)
    }

    /// 某行是否为图片占位行。
    ///
    /// 判定：该行的字符区间内**包含**占位标记（占位标记独占一段，
    /// 故正常情况下整行就是它；用 `contains` 容错"行首缩进把标记推后"）。
    ///
    /// - Parameters:
    ///   - line: 排版行（`charOffset`/`charLength`）。
    ///   - chapterText: 整章文本。
    ///   - token: 占位标记（`EpubTextExtractor.imagePlaceholderToken`）。
    public static func isPlaceholderLine(_ line: TypesetLine,
                                         chapterText: String,
                                         token: String) -> Bool {
        let ns = chapterText as NSString
        guard line.charOffset >= 0, line.charLength > 0,
              line.charOffset + line.charLength <= ns.length else { return false }
        let slice = ns.substring(with: NSRange(location: line.charOffset,
                                              length: line.charLength))
        return slice.contains(token)
    }

    /// 收集某页所有占位行的索引与对应绘制矩形（页面坐标系）。
    ///
    /// - Parameters:
    ///   - page: 当前页。
    ///   - chapterText: 整章文本。
    ///   - typography: 排版参数（取正文宽/边距/比例）。
    ///   - containerSize: 容器尺寸。
    ///   - yTopPositions: 每行顶部 y（与渲染同源）。
    ///   - token: 占位标记。
    /// - Returns: `(lineIndex, rect)` 列表；rect 已含段间距。
    public static func placeholders(in page: TypesetPage,
                                    chapterText: String,
                                    typography: ReaderTypography,
                                    containerSize: CGSize,
                                    yTopPositions: [CGFloat],
                                    token: String) -> [(lineIndex: Int, rect: CGRect)] {
        let contentWidth = containerSize.width
            - CGFloat(typography.insets.leading)
            - CGFloat(typography.insets.trailing)
        let size = placeholderSize(contentWidth: contentWidth,
                                   aspect: typography.imagePlaceholderAspect)
        var result: [(Int, CGRect)] = []
        for (i, line) in page.lines.enumerated() {
            guard i < yTopPositions.count,
                  isPlaceholderLine(line, chapterText: chapterText, token: token) else { continue }
            // 占位块从该行顶部开始，向下延伸（可能跨过下方空白行——
            // 占位标记独占一段，段后为空行，视觉上不冲突）
            let rect = CGRect(x: CGFloat(typography.insets.leading),
                              y: yTopPositions[i] + paragraphSpacing / 2,
                              width: size.width,
                              height: size.height)
            result.append((i, rect))
        }
        return result
    }
}
