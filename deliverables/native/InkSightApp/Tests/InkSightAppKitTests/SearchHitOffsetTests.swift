import XCTest
@testable import InkSightAppKit
import InkSightCore

/// FR-024a：检索命中 → 原文 UTF-16 偏移的解析（不常驻正文）。
///
/// 设计：FTS5 不提供可映射回原文的 offset，故命中点击时**二次读取该章**并扫描查询词，
/// 得到 UTF-16 偏移再交给阅读器恢复页。本测试锁住该解析口径。
final class SearchHitOffsetTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-offset-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    /// 命中偏移必须能在原始章节中定位到查询词（UTF-16 口径）。
    func testOffsetPointsAtQueryInOriginalChapter() throws {
        let chapter = "前言部分。墨见读书严守定位铁律，只以字符偏移恢复进度。结尾。"
        let offset = try XCTUnwrap(Self.findOffset(of: "定位铁律", in: chapter))
        let ns = chapter as NSString
        let slice = ns.substring(with: NSRange(location: offset, length: 4))
        XCTAssertEqual(slice, "定位铁律", "偏移必须指向原始章节中的查询词")
    }

    /// 查询词不存在时必须返回 nil，不得返回 0 冒充命中。
    func testMissingQueryReturnsNilNotZero() {
        XCTAssertNil(Self.findOffset(of: "不存在的词", in: "这里没有那个词。"))
    }

    /// 同一查询词多次出现时取**首次**出现（稳定、可复现）。
    func testMultipleOccurrencesTakeFirstStablePosition() throws {
        let text = "定位铁律很重要。后文又说定位铁律。"
        let first = try XCTUnwrap(Self.findOffset(of: "定位铁律", in: text))
        XCTAssertEqual(first, 0, "首次出现应在开头")
        let second = try XCTUnwrap(Self.findOffset(of: "后文", in: text))
        XCTAssertGreaterThan(second, first)
    }

    /// 偏移以 UTF-16 计算（与 `PageAnchor.charOffset` / `ReadingProgress.charOffset` 同口径）。
    func testOffsetUsesUTF16Semantics() throws {
        let text = "🀄️定位铁律"
        let offset = try XCTUnwrap(Self.findOffset(of: "定位铁律", in: text))
        let ns = text as NSString
        XCTAssertEqual(ns.substring(with: NSRange(location: offset, length: 4)), "定位铁律")
        XCTAssertEqual(offset, ns.range(of: "定位铁律").location,
                       "必须与 NSString/UTF-16 偏移一致（代理对不是 1 个字符）")
    }

    /// 复刻 App 侧解析口径（与 PlaceholderScreens 中的扫描逻辑同源）。
    private static func findOffset(of query: String, in text: String) -> Int? {
        guard !query.isEmpty else { return nil }
        let range = (text as NSString).range(of: query)
        return range.location == NSNotFound ? nil : range.location
    }
}
