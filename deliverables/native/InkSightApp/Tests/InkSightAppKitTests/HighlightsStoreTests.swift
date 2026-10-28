import XCTest
@testable import InkSightAppKit

/// FR-013 划线/笔记契约测试。
final class HighlightsStoreTests: XCTestCase {

    private var tempDir: URL!
    private var store: HighlightsStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-hl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = HighlightsStore(fileURL: tempDir.appendingPathComponent("h.json"))
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func makeHighlight(offset: Int, note: String = "", tags: [String] = []) -> Highlight {
        Highlight(bookID: "b1", chapterID: 1, charOffset: offset, charLength: 4,
                  fingerprint: 0xABCD, selectedText: "选中的句子", note: note, tags: tags)
    }

    /// 添加后可读回；按创建时间倒序。
    func testAddAndRead() {
        store.add(makeHighlight(offset: 10))
        store.add(makeHighlight(offset: 20))
        XCTAssertEqual(store.allHighlights().count, 2)
        XCTAssertEqual(store.allHighlights().first?.charOffset, 20, "按创建时间倒序")
    }

    /// 某书某章按偏移排序（供阅读器叠加显示）。
    func testChapterHighlightsSortedByOffset() {
        store.add(makeHighlight(offset: 50))
        store.add(makeHighlight(offset: 10))
        store.add(makeHighlight(offset: 30))
        let chapter = store.highlights(bookID: "b1", chapterID: 1)
        XCTAssertEqual(chapter.map(\.charOffset), [10, 30, 50])
    }

    /// 删除按 (bookID, chapterID, charOffset) 精确匹配。
    func testRemoveByAnchor() {
        store.add(makeHighlight(offset: 10))
        store.add(makeHighlight(offset: 20))
        store.remove(bookID: "b1", chapterID: 1, charOffset: 10)
        XCTAssertEqual(store.allHighlights().count, 1)
        XCTAssertEqual(store.allHighlights().first?.charOffset, 20)
    }

    /// 按标签聚合（FR-022 跨书聚合的基础）。
    func testFilterByTag() {
        store.add(makeHighlight(offset: 10, tags: ["励志"]))
        store.add(makeHighlight(offset: 20, tags: ["金句"]))
        store.add(makeHighlight(offset: 30, tags: ["励志"]))
        XCTAssertEqual(store.highlights(tag: "励志").count, 2)
        XCTAssertEqual(store.highlights(tag: "金句").count, 1)
    }

    /// Codable 落盘（经 Persist 门面）往返：无 pageIndex 字段。
    func testPersistRoundTripNoPageIndex() throws {
        store.add(makeHighlight(offset: 42, note: "好句", tags: ["金句"]))
        try store.persist()

        let loaded = HighlightsStore(fileURL: store.fileURL)
        try loaded.load()
        let restored = try XCTUnwrap(loaded.allHighlights().first)
        XCTAssertEqual(restored.charOffset, 42)
        XCTAssertEqual(restored.note, "好句")
        XCTAssertEqual(restored.tags, ["金句"])

        // 定位铁律：落盘 JSON 不得含 pageIndex 键
        let data = try store.encodedJSON()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let keys = Set(json[0].keys)
        XCTAssertFalse(keys.contains("pageIndex"), "划线持久化不得出现 pageIndex（定位铁律）")
    }

    /// 选中文本提取：UTF-16 口径，越界返回 nil。
    func testSelectedTextExtraction() {
        let chapter = "这是第一句话。这是第二句话。"
        // UTF-16：这0 是1 第2 一3 句4 话5 。6 这7 是8 第9 二10 句11 话12
        XCTAssertEqual(Highlight.selectedText(from: chapter, offset: 2, length: 3), "第一句")
        XCTAssertEqual(Highlight.selectedText(from: chapter, offset: 7, length: 5), "这是第二句")
        XCTAssertNil(Highlight.selectedText(from: chapter, offset: 0, length: 999), "越界返回 nil")
        XCTAssertNil(Highlight.selectedText(from: chapter, offset: -1, length: 2), "负偏移返回 nil")
    }
}
