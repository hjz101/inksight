import XCTest
@testable import InkSightAppUI
import Foundation

/// FR-007 封面渲染契约测试。
final class BookCoverTests: XCTestCase {

    private func source(_ name: String) throws -> String {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/InkSightAppUI")
        let raw = try String(contentsOf: base.appendingPathComponent(name), encoding: .utf8)
        return raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return !t.hasPrefix("//") && !t.hasPrefix("///") && !t.hasPrefix("*")
            }.joined(separator: "\n")
    }

    /// 有封面 → 真实图；aspect-fill（不裁坏）。
    func testRealCoverUsesAspectFill() throws {
        let src = try source("BookCoverView.swift")
        XCTAssertTrue(src.contains("aspectRatio(contentMode: .fill)"), "须 aspect-fill")
    }

    /// 无封面 → **配色占位**，不用第三方书封。
    func testPlaceholderIsGeneratedColor() throws {
        let src = try source("BookCoverView.swift")
        XCTAssertTrue(src.contains("LinearGradient"), "占位须用配色渐变")
        XCTAssertFalse(src.contains("AsyncImage"), "不得加载第三方书封")
        XCTAssertTrue(src.contains("书名首字") || src.contains("prefix(1)"), "占位显示首字")
    }

    /// 占位色**稳定**（同书名恒定；用 random 会闪）。
    func testPlaceholderHueIsStable() {
        let a = BookCoverView.stableHue(for: "红楼梦")
        let b = BookCoverView.stableHue(for: "红楼梦")
        XCTAssertEqual(a, b, "同书名占位色必须恒定（否则每次重建会闪）")
        let c = BookCoverView.stableHue(for: "西游记")
        XCTAssertNotEqual(a, c, "不同书应有不同色")
        XCTAssertTrue((0...1).contains(a), "色相须在 0…1")
    }

    /// 书架行接了封面。
    func testShelfRowUsesCover() throws {
        let src = try source("PlaceholderScreens.swift")
        XCTAssertTrue(src.contains("BookCoverView(title: item.title"),
                      "书架行须渲染封面")
    }
}
