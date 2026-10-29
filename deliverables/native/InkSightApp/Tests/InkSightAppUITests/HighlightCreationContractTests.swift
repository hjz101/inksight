import XCTest
@testable import InkSightAppUI
import Foundation

/// FR-013 划线创建契约测试（长按选句 → 划线，3 步内完成）。
final class HighlightCreationContractTests: XCTestCase {

    private func readerSource() throws -> String {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/InkSightAppUI")
        let raw = try String(contentsOf: base.appendingPathComponent("ReaderSurface.swift"),
                             encoding: .utf8)
        return raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return !t.hasPrefix("//") && !t.hasPrefix("///") && !t.hasPrefix("*")
            }
            .joined(separator: "\n")
    }

    /// 长按手势已接线（DragGesture + 0.5s 延迟判定）。
    func testLongPressWired() throws {
        let src = try readerSource()
        XCTAssertTrue(src.contains("presentSelectionActions"),
                      "须有长按→选句入口")
        XCTAssertTrue(src.contains("Task.sleep"), "须有长按延时判定")
    }

    /// 选中后弹出**划线操作面板**（划线/笔记/标签/取消，3 步内）。
    ///
    /// D-97：图标已从 `Label(_:systemImage:)` 换成自绘 `InkIcon + Text`
    /// （FR-028 第 ① 项全量替换），断言随之改查 `Text` 文案。
    func testSelectionActionsPanel() throws {
        let src = try readerSource()
        XCTAssertTrue(src.contains("Text(\"划线\")"), "须有划线动作")
        XCTAssertTrue(src.contains("Text(\"笔记\")"), "须有笔记动作")
        XCTAssertTrue(src.contains("Text(\"标签\")"), "须有标签动作")
        XCTAssertTrue(src.contains("Text(\"取消\")"), "须有取消")
    }

    /// 划线落库走 `HighlightsStore`（`charOffset + charLength + fingerprint`）。
    func testHighlightPersistedViaStore() throws {
        let src = try readerSource()
        XCTAssertTrue(src.contains("HighlightsStore()"), "划线须经 HighlightsStore 落库")
        XCTAssertTrue(src.contains("charOffset: sel.charOffset"), "选区以 charOffset 表达")
        XCTAssertTrue(src.contains("selectedText: sel.selectedText"), "须保存选中文本")
    }

    /// 定位铁律：划线锚点无 pageIndex。
    func testNoPageIndexInHighlight() throws {
        let src = try readerSource()
        guard let range = src.range(of: "private func addHighlight") else {
            return XCTFail("找不到 addHighlight")
        }
        let body = String(src[range.lowerBound...].prefix(700))
        XCTAssertFalse(body.contains("pageIndex"), "划线锚点不得含 pageIndex（定位铁律）")
    }

    /// 成功划线后有诚实反馈 toast。
    func testHighlightToast() throws {
        let src = try readerSource()
        XCTAssertTrue(src.contains("已划线"), "划线成功须有反馈")
    }
}
