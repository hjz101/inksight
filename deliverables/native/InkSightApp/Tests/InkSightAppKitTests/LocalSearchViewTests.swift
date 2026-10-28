import XCTest
@testable import InkSightAppUI

/// FR-024a 检索视图的展示逻辑测试（snippet 还原为可读文本）。
///
/// FTS5 的中文按字索引会在字符间插空格（「定 位 铁 律」），
/// 直接展示会显得破碎；`prettySnippet` 负责把汉字间的空格去掉。
final class LocalSearchViewTests: XCTestCase {

    /// 汉字间空格被去掉，还原成连续中文。
    func testPrettySnippetRemovesCJKSpace() {
        XCTAssertEqual(LocalSearchView.prettySnippet("定 位 铁 律"), "定位铁律")
        XCTAssertEqual(LocalSearchView.prettySnippet("严 守 定 位 铁 律 只 以"), "严守定位铁律只以")
    }

    /// 英文词之间的空格**必须保留**（不能被误删）。
    func testPrettySnippetKeepsLatinSpaces() {
        XCTAssertEqual(LocalSearchView.prettySnippet("hello world"), "hello world")
        XCTAssertEqual(LocalSearchView.prettySnippet("Swift UI test"), "Swift UI test")
    }

    /// 中英混排：汉字间空格去掉，英文词内/间空格保留。
    func testPrettySnippetMixedContent() {
        XCTAssertEqual(LocalSearchView.prettySnippet("用 Swift 写 代 码"), "用 Swift 写代码")
    }

    /// FTS5 命中标记 `…` 保留（它标识命中位置，不该被清理掉）。
    func testPrettySnippetKeepsHitMarkers() {
        let raw = "…定… …位… …铁…"
        let pretty = LocalSearchView.prettySnippet(raw)
        XCTAssertTrue(pretty.contains("…"), "命中标记应保留")
        XCTAssertTrue(pretty.contains("定"), "命中字应保留")
    }

    /// 空输入不崩。
    func testPrettySnippetEmpty() {
        XCTAssertEqual(LocalSearchView.prettySnippet(""), "")
    }
}
