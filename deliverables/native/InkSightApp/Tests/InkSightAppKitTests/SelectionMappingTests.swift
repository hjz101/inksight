import XCTest
@testable import InkSightAppKit
import CoreGraphics
import InkSightCore

/// FR-013 长按选句的坐标→字符映射测试。
final class SelectionMappingTests: XCTestCase {

    /// 用**真实 `Typesetter` 排版**生成页与几何（不手工构造，避免签名漂移）。
    private func makePage() -> (page: TypesetPage, text: String, geo: [SelectionMapping.LineGeometry]) {
        let text = "第一行内容\n第二行内容\n第三行内容"
        let typography = ReaderTypography.default
        let typesetter = Typesetter(text: text, typography: typography,
                                    containerSize: CGSize(width: 300, height: 200),
                                    kinsoku: Kinsoku(version: 1, lineStartForbidden: [], lineEndForbidden: []))
        let result = typesetter.typesetChapter()
        guard let page = result.pages.first else {
            fatalError("排版失败")
        }
        let geo = SelectionMapping.geometries(for: page, typography: typography)
        return (page, text, geo)
    }

    /// 点在第 2 行行盒内 → 选中第 2 行文本。
    func testSelectSecondLine() {
        let (page, text, geo) = makePage()
        // 第 2 行的 y 范围：top + 行高×1 … top + 行高×2
        let lineHeight = CGFloat(ReaderTypography.default.lineHeight)
        let y = CGFloat(ReaderTypography.default.insets.top) + lineHeight * 1.5
        let selection = SelectionMapping.selectLine(
            at: CGPoint(x: 50, y: y), page: page, chapterText: text, geometries: geo)
        XCTAssertNotNil(selection)
        XCTAssertEqual(selection?.charOffset, 6)
        XCTAssertEqual(selection?.selectedText, "第二行内容")
    }

    /// 点在第 1 行 → 选中第 1 行。
    func testSelectFirstLine() {
        let (page, text, geo) = makePage()
        let y = CGFloat(ReaderTypography.default.insets.top) + 4
        let selection = SelectionMapping.selectLine(
            at: CGPoint(x: 50, y: y), page: page, chapterText: text, geometries: geo)
        XCTAssertEqual(selection?.charOffset, 0)
        XCTAssertEqual(selection?.selectedText, "第一行内容")
    }

    /// 点落在行盒外（如页边距空白）→ nil（诚实：不假装选中）。
    func testPointOutsideLinesReturnsNil() {
        let (page, text, geo) = makePage()
        // 左侧边距内（x < leadingX）
        let selection = SelectionMapping.selectLine(
            at: CGPoint(x: 2, y: 10), page: page, chapterText: text, geometries: geo)
        XCTAssertNil(selection)
    }

    /// 点超出最后一行下边界 → nil。
    func testPointBelowLastLineReturnsNil() {
        let (page, text, geo) = makePage()
        let bottom = geo.last.map { $0.yTop + $0.height } ?? 0
        let selection = SelectionMapping.selectLine(
            at: CGPoint(x: 50, y: bottom + 50), page: page, chapterText: text, geometries: geo)
        XCTAssertNil(selection)
    }

    /// 选区以 charOffset + charLength 表达（定位铁律，无 pageIndex）。
    func testSelectionUsesCharOffset() {
        let (page, text, geo) = makePage()
        let y = CGFloat(ReaderTypography.default.insets.top) + 4
        let selection = SelectionMapping.selectLine(
            at: CGPoint(x: 50, y: y), page: page, chapterText: text, geometries: geo)
        XCTAssertEqual(selection?.charOffset, 0)
        XCTAssertEqual(selection?.charLength, 5)
    }

    /// 行几何与行数对齐（每行一条）。
    func testGeometriesMatchLineCount() {
        let (page, _, geo) = makePage()
        XCTAssertEqual(geo.count, page.lines.count)
    }
}
