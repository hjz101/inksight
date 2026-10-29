import XCTest
@testable import InkSightAppKit
import InkSightCore

/// 默认排版**必须逐值对齐 PRD 正文样式基线**。
///
/// D-99 发现的真实偏差：`ReaderTypography.default` 曾是
/// `fontSize 18 / 段前 8 / 段后 8 / 缩进 28 / 比例 1.5`——全部不符 PRD 基线，
/// 且字号 18 **不在 FR-009 档位集 {19,20,21}** 内（D-72 引入档位制时漏了收口）。
final class DefaultTypographyBaselineTests: XCTestCase {

    /// 字号必须是档位默认值（FR-009）。
    func testDefaultFontSizeIsTierDefault() {
        XCTAssertEqual(ReaderTypography.default.fontSize, TypographyTiers.defaultFontSize,
                       "默认字号必须 = 档位默认（20），不得用档位外的值")
        XCTAssertTrue(TypographyTiers.isValidFontSize(ReaderTypography.default.fontSize),
                      "默认字号必须在档位集内")
    }

    /// 默认排版**必须通过档位归一化后不变**（即本身就是合法值）。
    func testDefaultIsAlreadyNormalized() {
        let normalized = TypographyTiers.normalize(.default)
        XCTAssertEqual(normalized, ReaderTypography.default,
                       "默认排版应已是归一化后的合法值（幂等）")
    }

    /// 行高为 1.75（PRD 默认档）。
    func testDefaultLineHeight() {
        XCTAssertEqual(ReaderTypography.default.lineHeightMultiplier, 1.75)
    }

    /// 段前 12 / 段后 0（PRD：段间间距 12pt，不由行盒余量叠加）。
    func testDefaultParagraphSpacing() {
        XCTAssertEqual(ReaderTypography.default.paragraphSpacingBefore, 12,
                       "PRD：段前 12pt")
        XCTAssertEqual(ReaderTypography.default.paragraphSpacingAfter, 0,
                       "PRD：段后 0（视觉间距只由段前给）")
    }

    /// 缩进默认 0（PRD：首行缩进默认 0）。
    func testDefaultIndentIsZero() {
        XCTAssertEqual(ReaderTypography.default.indent, 0, "PRD：首行缩进默认 0pt")
    }

    /// 图片占位比例 3:4（FR-018-ac c 默认值）。
    func testDefaultImageAspect() {
        XCTAssertEqual(ReaderTypography.default.imagePlaceholderAspect, 0.75, accuracy: 0.001,
                       "FR-018-ac c：默认 3:4 = 0.75")
    }

    /// 行盒 = 字号 × 倍数（D-31 唯一真源口径）。
    func testLineBoxFormula() {
        XCTAssertEqual(ReaderTypography.default.lineHeight, 20 * 1.75, accuracy: 0.001,
                       "行盒 = 20 × 1.75 = 35pt（D-31）")
    }
}
