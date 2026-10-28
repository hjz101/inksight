import XCTest
@testable import InkSightAppKit
import InkSightCore

/// FR-009 排版档位制契约测试。
final class TypographyTiersTests: XCTestCase {

    /// 档位定义与 PRD 一致。
    func testTierDefinitions() {
        XCTAssertEqual(TypographyTiers.fontSizes, [19, 20, 21])
        XCTAssertEqual(TypographyTiers.defaultFontSize, 20)
        XCTAssertEqual(TypographyTiers.lineHeights, [1.70, 1.75, 1.85])
        XCTAssertEqual(TypographyTiers.defaultLineHeight, 1.75)
        XCTAssertEqual(TypographyTiers.margins, [16, 20, 24])
        // 段前/段后固定
        XCTAssertEqual(TypographyTiers.paragraphSpacingBefore, 12)
        XCTAssertEqual(TypographyTiers.paragraphSpacingAfter, 0)
    }

    /// **12pt 不开放**（PRD 明文：12pt 不是多一档字号，是多一整套组合）。
    func test12ptIsNotATier() {
        XCTAssertFalse(TypographyTiers.fontSizes.contains(12))
        XCTAssertFalse(TypographyTiers.isValidFontSize(12))
        // 越界的 12 应 snap 到最近的合法档 19
        XCTAssertEqual(TypographyTiers.normalizeFontSize(12), 19)
    }

    /// 边距默认按屏宽判定（≤375→16，>375→20）。
    func testDefaultMarginByScreenWidth() {
        XCTAssertEqual(TypographyTiers.defaultMargin(screenWidth: 375), 16)
        XCTAssertEqual(TypographyTiers.defaultMargin(screenWidth: 320), 16)
        XCTAssertEqual(TypographyTiers.defaultMargin(screenWidth: 393), 20)
        XCTAssertEqual(TypographyTiers.defaultMargin(screenWidth: 430), 20)
    }

    /// 越界值 snap 到最近档（旧滑块允许 14…28，会写出非法档位）。
    func testOutOfRangeValuesSnapToNearestTier() {
        XCTAssertEqual(TypographyTiers.normalizeFontSize(14), 19)
        XCTAssertEqual(TypographyTiers.normalizeFontSize(28), 21)
        XCTAssertEqual(TypographyTiers.normalizeFontSize(20.6), 21)
        XCTAssertEqual(TypographyTiers.normalizeFontSize(19.4), 19)
        XCTAssertEqual(TypographyTiers.normalizeLineHeight(1.2), 1.70)
        XCTAssertEqual(TypographyTiers.normalizeLineHeight(2.4), 1.85)
        XCTAssertEqual(TypographyTiers.normalizeMargin(8), 16)
        XCTAssertEqual(TypographyTiers.normalizeMargin(48), 24)
    }

    /// 缩进：0 或 2×字号。
    func testIndentIsZeroOrDoubleFontSize() {
        XCTAssertEqual(TypographyTiers.indent(enabled: false, fontSize: 20), 0)
        XCTAssertEqual(TypographyTiers.indent(enabled: true, fontSize: 20), 40)
        XCTAssertEqual(TypographyTiers.indent(enabled: true, fontSize: 19), 38)
        XCTAssertTrue(TypographyTiers.isValidIndent(0, fontSize: 20))
        XCTAssertTrue(TypographyTiers.isValidIndent(40, fontSize: 20))
        XCTAssertFalse(TypographyTiers.isValidIndent(28, fontSize: 20), "28 不是 0 也不是 2×20")
    }

    /// **normalize 把整份排版参数压回合法档位**（防历史越界值继续生效）。
    func testNormalizeTypography() {
        // 模拟旧滑块写出的非法预设
        let illegal = ReaderTypography(
            fontID: "PingFangSC-Regular",
            fontSize: 14,                    // 非法 → 19
            lineHeightMultiplier: 1.2,       // 非法 → 1.70
            paragraphSpacingBefore: 8,       // 非固定值 → 12
            paragraphSpacingAfter: 8,        // 非固定值 → 0
            insets: ReaderInsets(top: 24, leading: 8, bottom: 24, trailing: 8),  // 8 → 16
            indent: 28,                      // 非法（非 0 非 2×19）→ 0
            imagePlaceholderAspect: 1.5
        )
        let fixed = TypographyTiers.normalize(illegal)
        XCTAssertEqual(fixed.fontSize, 19)
        XCTAssertEqual(fixed.lineHeightMultiplier, 1.70)
        XCTAssertEqual(fixed.paragraphSpacingBefore, 12, "段前固定 12")
        XCTAssertEqual(fixed.paragraphSpacingAfter, 0, "段后固定 0")
        XCTAssertEqual(fixed.insets.leading, 16)
        XCTAssertEqual(fixed.insets.trailing, 16)
        XCTAssertEqual(fixed.indent, 0)
        XCTAssertEqual(fixed.imagePlaceholderAspect, 1.5, "占位比例不是档位项，保持不变")
    }

    /// 合法值归一化后不变（幂等）。
    func testNormalizeIsIdempotentForLegalValues() {
        let legal = ReaderTypography(
            fontID: "PingFangSC-Regular", fontSize: 20, lineHeightMultiplier: 1.75,
            paragraphSpacingBefore: 12, paragraphSpacingAfter: 0,
            insets: ReaderInsets(top: 24, leading: 20, bottom: 28, trailing: 20),
            indent: 40, imagePlaceholderAspect: 0.75
        )
        XCTAssertEqual(TypographyTiers.normalize(legal), legal)
    }
}
