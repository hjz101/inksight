import XCTest
@testable import InkSightAppKit
import InkSightCore
import CoreGraphics

/// FR-018-ac c 图片占位几何契约测试。
final class ImagePlaceholderLayoutTests: XCTestCase {

    /// 占位块**宽 = 正文宽**（容器宽 − 左右边距）。
    func testWidthEqualsContentWidth() {
        let size = ImagePlaceholderLayout.placeholderSize(contentWidth: 353, aspect: 0.75)
        XCTAssertEqual(size.width, 353, "宽须等于正文宽")
    }

    /// **默认 3:4**（宽/高 = 0.75 → 高 = 宽/0.75）。
    func testDefaultAspectIsThreeToFour() {
        let size = ImagePlaceholderLayout.placeholderSize(contentWidth: 300, aspect: 0.75)
        XCTAssertEqual(size.height, 400, accuracy: 0.01, "3:4 图片高 = 300/0.75 = 400")
    }

    /// aspect 变化 → 高度跟着变（**不得"源给了尺寸就用源的"**，比例恒由排版参数决定）。
    func testAspectDrivesHeight() {
        let wide = ImagePlaceholderLayout.placeholderSize(contentWidth: 300, aspect: 1.5)
        let tall = ImagePlaceholderLayout.placeholderSize(contentWidth: 300, aspect: 0.5)
        XCTAssertEqual(wide.height, 200, accuracy: 0.01)
        XCTAssertEqual(tall.height, 600, accuracy: 0.01)
        XCTAssertLessThan(wide.height, tall.height, "比例越大（越宽）高度越小")
    }

    /// 非法 aspect 回落 0.75（不崩、不产生 NaN/极大值）。
    func testInvalidAspectFallsBack() {
        let size = ImagePlaceholderLayout.placeholderSize(contentWidth: 300, aspect: 0)
        XCTAssertEqual(size.height, 400, accuracy: 0.01, "aspect=0 应回落 0.75")
        XCTAssertTrue(size.height.isFinite)
    }

    /// 段间距 16pt（PRD）。
    func testParagraphSpacingConstant() {
        XCTAssertEqual(ImagePlaceholderLayout.paragraphSpacing, 16, "图与段间距 16pt")
    }

    // MARK: - 行识别

    private func makeTypeset(_ text: String) -> (TypesetPage, ReaderTypography) {
        let typography = ReaderTypography.default
        let typesetter = Typesetter(text: text, typography: typography,
                                    containerSize: CGSize(width: 300, height: 400),
                                    kinsoku: Kinsoku(version: 1, lineStartForbidden: [],
                                                     lineEndForbidden: []))
        let result = typesetter.typesetChapter()
        return (result.pages[0], typography)
    }

    /// 含占位标记的行被识别为占位行。
    func testPlaceholderLineDetected() {
        let token = EpubTextExtractor.imagePlaceholderToken
        let text = "第一段文字。\n\(token)\n第二段文字。"
        let (page, _) = makeTypeset(text)
        let found = page.lines.contains {
            ImagePlaceholderLayout.isPlaceholderLine($0, chapterText: text, token: token)
        }
        XCTAssertTrue(found, "含占位标记的行应被识别")
    }

    /// 纯文字行不被误判。
    func testNormalLineNotDetected() {
        let token = EpubTextExtractor.imagePlaceholderToken
        let text = "只有文字的一行。\n另一行文字。"
        let (page, _) = makeTypeset(text)
        for line in page.lines {
            XCTAssertFalse(ImagePlaceholderLayout.isPlaceholderLine(line,
                                                                    chapterText: text,
                                                                    token: token),
                           "纯文字行不应被当作占位")
        }
    }

    /// 页内占位块集合：位置在正文左边界，宽度=正文宽。
    func testPlaceholdersGeometry() {
        let token = EpubTextExtractor.imagePlaceholderToken
        let text = "前言文字。\n\(token)\n后记文字。"
        let (page, typography) = makeTypeset(text)
        let comp = CoreTextLineCompositor(text: text, typography: typography)
        let ys = comp.yTopPositions(for: page)
        let phs = ImagePlaceholderLayout.placeholders(
            in: page, chapterText: text, typography: typography,
            containerSize: CGSize(width: 300, height: 400),
            yTopPositions: ys, token: token)
        XCTAssertFalse(phs.isEmpty, "应算出至少一个占位块")
        if let first = phs.first {
            XCTAssertEqual(first.rect.minX, CGFloat(typography.insets.leading),
                           "占位块须从正文左边界开始")
            let expectedWidth = 300 - CGFloat(typography.insets.leading)
                - CGFloat(typography.insets.trailing)
            XCTAssertEqual(first.rect.width, expectedWidth, accuracy: 0.01)
        }
    }
}
