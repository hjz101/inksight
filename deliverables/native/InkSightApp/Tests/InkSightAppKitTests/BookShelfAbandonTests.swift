import XCTest
@testable import InkSightAppKit
import InkSightCore

/// FR-035 手动弃读契约测试。
final class BookShelfAbandonTests: XCTestCase {

    private var tempDir: URL!
    private var shelf: BookShelfStore!
    private var progressStore: ReadingProgressStore!
    private var bookmarksStore: BookmarksStore!
    private var highlightsStore: HighlightsStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-abandon-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        shelf = BookShelfStore()
        progressStore = ReadingProgressStore()
        bookmarksStore = BookmarksStore(fileURL: tempDir.appendingPathComponent("bm.json"))
        highlightsStore = HighlightsStore(fileURL: tempDir.appendingPathComponent("hl.json"))
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func importBook(_ id: String, title: String = "书") -> BookShelfItem {
        let data = Data("第一章 开头\n内容".utf8)
        return shelf.importLocalBook(bookID: id, title: title, fileData: data)
    }

    /// 弃读移除书架项。
    func testAbandonRemovesFromShelf() {
        importBook("b1")
        importBook("b2")
        XCTAssertTrue(shelf.abandon(bookID: "b1"))
        XCTAssertNil(shelf.item(for: "b1"), "弃读后应从书架移除")
        XCTAssertNotNil(shelf.item(for: "b2"), "其它书不受影响")
    }

    /// 弃读不存在的书返回 false。
    func testAbandonMissingReturnsFalse() {
        XCTAssertFalse(shelf.abandon(bookID: "ghost"))
    }

    /// **必须清理关联数据**（进度/书签/划线）——否则就是"幽灵书"。
    func testAbandonCleansAssociatedData() {
        let item = importBook("b1")
        progressStore.record(ReadingProgress(bookID: "b1", chapterID: 0, charOffset: 10, fingerprint: 1))
        bookmarksStore.add(Bookmark(bookID: "b1", chapterID: 0, charOffset: 5,
                                    fingerprint: 1, preview: "预览"))
        highlightsStore.add(Highlight(bookID: "b1", chapterID: 0, charOffset: 3, charLength: 2,
                                      fingerprint: 1, selectedText: "正文", tags: []))

        _ = shelf.abandon(bookID: "b1",
                          progressStore: progressStore,
                          bookmarksStore: bookmarksStore,
                          highlightsStore: highlightsStore)

        XCTAssertNil(progressStore.progress(for: "b1"), "弃读应清进度")
        XCTAssertTrue(bookmarksStore.allBookmarks().isEmpty, "弃读应清书签")
        XCTAssertTrue(highlightsStore.allHighlights().isEmpty, "弃读应清划线")
    }

    /// 弃读后书架为空 → 诚实空态（不残留条目）。
    func testAbandonLastBookLeavesEmptyShelf() {
        importBook("only")
        _ = shelf.abandon(bookID: "only")
        XCTAssertTrue(shelf.items.isEmpty)
        XCTAssertNil(shelf.currentItem)
    }

    /// 弃读不影响其它书的关联数据。
    func testAbandonIsIsolatedPerBook() {
        importBook("b1")
        importBook("b2")
        progressStore.record(ReadingProgress(bookID: "b2", chapterID: 0, charOffset: 99, fingerprint: 2))

        _ = shelf.abandon(bookID: "b1", progressStore: progressStore)
        XCTAssertEqual(progressStore.progress(for: "b2")?.charOffset, 99,
                       "弃读 b1 不得影响 b2 的进度")
    }
}
