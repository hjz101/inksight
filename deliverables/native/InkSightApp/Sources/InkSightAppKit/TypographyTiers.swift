import Foundation
import InkSightCore

// MARK: - TypographyTiers（FR-009 排版档位制）

/// 排版档位定义（PRD FR-009 ＋ 正文样式基线）。
///
/// **档位制不是滑块**——PRD 明文给出的可选项是**离散档位**，任意值属于越界：
/// - 字号：19 / **20（默认）** / 21 pt（**12pt 不开放**：它会让"高对比"变成第 4 个主题变体，
///   校验组合从 3×N 变 4×N，"12pt 不是多一档字号、是多一整套组合"）；
/// - 行高：1.70 / **1.75** / 1.85（行盒 `min == max == 字号×倍数`，D-31）；
/// - 边距：16 / 20 / 24 pt（首次启动按屏宽定默认：≤375pt→16、>375pt→20）；
/// - 段前 12pt、段后 0pt：**固定值，不是用户可调项**（正文样式基线）；
/// - 缩进：0（默认）/ 2×字号（20pt→40pt）。
public enum TypographyTiers {

    /// 字号档位（pt）。
    public static let fontSizes: [Double] = [19, 20, 21]
    /// 字号默认档。
    public static let defaultFontSize: Double = 20

    /// 行高档位（倍数）。
    public static let lineHeights: [Double] = [1.70, 1.75, 1.85]
    /// 行高默认档。
    public static let defaultLineHeight: Double = 1.75

    /// 边距档位（pt，左右对称）。
    public static let margins: [Double] = [16, 20, 24]
    /// 边距默认档（按屏宽判定）。
    public static func defaultMargin(screenWidth: Double) -> Double {
        screenWidth <= 375 ? 16 : 20
    }

    /// 段前间距（固定 12pt，非用户可调）。
    public static let paragraphSpacingBefore: Double = 12
    /// 段后间距（固定 0pt，非用户可调）。
    public static let paragraphSpacingAfter: Double = 0

    /// 缩进：0 或 2×字号。
    public static func indent(enabled: Bool, fontSize: Double) -> Double {
        enabled ? fontSize * 2 : 0
    }

    // MARK: - 归一化（把越界值 snap 到最近合法档）

    /// 把任意字号 snap 到最近合法档（越界值不得进入排版）。
    public static func normalizeFontSize(_ value: Double) -> Double {
        nearest(value, in: fontSizes)
    }

    /// 把任意行高倍数 snap 到最近合法档。
    public static func normalizeLineHeight(_ value: Double) -> Double {
        nearest(value, in: lineHeights)
    }

    /// 把任意边距 snap 到最近合法档。
    public static func normalizeMargin(_ value: Double) -> Double {
        nearest(value, in: margins)
    }

    /// 判定某字号是否合法档位。
    public static func isValidFontSize(_ value: Double) -> Bool { fontSizes.contains(value) }
    /// 判定某行高是否合法档位。
    public static func isValidLineHeight(_ value: Double) -> Bool { lineHeights.contains(value) }
    /// 判定某边距是否合法档位。
    public static func isValidMargin(_ value: Double) -> Bool { margins.contains(value) }
    /// 判定某缩进是否合法（0 或 2×字号）。
    public static func isValidIndent(_ value: Double, fontSize: Double) -> Bool {
        value == 0 || value == fontSize * 2
    }

    /// 把排版参数**归一化到合法档位**（越界值 snap，固定项写死）。
    ///
    /// 用途：读取持久化预设/备份导入时，防止历史越界值继续生效
    /// （此前设置页滑块允许 14…28pt，会写出非法档位）。
    public static func normalize(_ t: ReaderTypography) -> ReaderTypography {
        ReaderTypography(
            fontID: t.fontID,
            fontSize: normalizeFontSize(t.fontSize),
            lineHeightMultiplier: normalizeLineHeight(t.lineHeightMultiplier),
            paragraphSpacingBefore: paragraphSpacingBefore,   // 固定
            paragraphSpacingAfter: paragraphSpacingAfter,     // 固定
            insets: ReaderInsets(top: t.insets.top,
                                 leading: normalizeMargin(t.insets.leading),
                                 bottom: t.insets.bottom,
                                 trailing: normalizeMargin(t.insets.trailing)),
            indent: isValidIndent(t.indent, fontSize: normalizeFontSize(t.fontSize))
                ? t.indent : 0,
            imagePlaceholderAspect: t.imagePlaceholderAspect
        )
    }

    /// 最近档位。
    private static func nearest(_ value: Double, in tiers: [Double]) -> Double {
        tiers.min(by: { abs($0 - value) < abs($1 - value) }) ?? tiers[tiers.count / 2]
    }
}
