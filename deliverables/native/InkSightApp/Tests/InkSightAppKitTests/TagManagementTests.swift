import XCTest
@testable import InkSightAppKit
import InkSightCore

/// FR-022 标签管理（重命名/删除/使用统计）契约测试。
final class TagManagementTests: XCTestCase {

    private var tempDir: URL!
    private var store: HighlightsStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-tags-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = HighlightsStore(fileURL: tempDir.appendingPathComponent("h.json"))
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func add(offset: Int, tags: [String], book: String = "b1") {
        store.add(Highlight(bookID: book, chapterID: 0, charOffset: offset, charLength: 2,
                            fingerprint: 1, selectedText: "文本", tags: tags))
    }

    /// 重命名标签跨全部划线生效。
    func testRenameTagAcrossAllHighlights() {
        add(offset: 1, tags: ["摘录"])
        add(offset: 2, tags: ["摘录", "重要"])
        let affected = store.renameTag("摘录", to: "金句")
        XCTAssertEqual(affected, 2, "两条划线都应受影响")
        XCTAssertEqual(store.highlights(tag: "金句").count, 2)
        XCTAssertTrue(store.highlights(tag: "摘录").isEmpty, "旧标签应消失")
    }

    /// 重命名到**已存在的标签**时去重（不产生重复标签）。
    func testRenameToExistingTagDeduplicates() {
        add(offset: 1, tags: ["A", "B"])
        store.renameTag("A", to: "B")
        let h = store.allHighlights().first
        XCTAssertEqual(h?.tags, ["B"], "不应出现两个 B")
    }

    /// 重命名到空串被拒绝（0 影响，不破坏数据）。
    func testRenameToEmptyIsRejected() {
        add(offset: 1, tags: ["A"])
        XCTAssertEqual(store.renameTag("A", to: "   "), 0)
        XCTAssertEqual(store.allHighlights().first?.tags, ["A"], "数据不应被破坏")
    }

    /// 删除标签：从划线移除标签，**划线本身保留**。
    func testDeleteTagKeepsHighlight() {
        add(offset: 1, tags: ["A", "B"])
        let affected = store.deleteTag("A")
        XCTAssertEqual(affected, 1)
        XCTAssertEqual(store.allHighlights().count, 1, "划线本身应保留")
        XCTAssertEqual(store.allHighlights().first?.tags, ["B"])
    }

    /// 标签使用统计按次数降序。
    func testTagUsageSortedByCount() {
        add(offset: 1, tags: ["常用"])
        add(offset: 2, tags: ["常用"])
        add(offset: 3, tags: ["少见"])
        let usage = store.tagUsage()
        XCTAssertEqual(usage.first?.tag, "常用")
        XCTAssertEqual(usage.first?.count, 2)
        XCTAssertEqual(usage.last?.tag, "少见")
    }

    /// 跨书聚合（FR-022：一个标签跨书聚合）。
    func testTagsAggregateAcrossBooks() {
        add(offset: 1, tags: ["主题"], book: "b1")
        add(offset: 2, tags: ["主题"], book: "b2")
        XCTAssertEqual(store.highlights(tag: "主题").count, 2, "标签应跨书聚合")
    }
}
