import XCTest
@testable import InkSightAppKit

/// FR-011 书签契约测试（定位铁律：只存 charOffset + fingerprint，无 pageIndex）。
final class BookmarkTests: XCTestCase {

    private var tempDir: URL!
    private var store: BookmarksStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-bm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = BookmarksStore(fileURL: tempDir.appendingPathComponent("bm.json"))
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func make(offset: Int, chapter: Int = 1) -> Bookmark {
        Bookmark(bookID: "b1", chapterID: chapter, charOffset: offset,
                 fingerprint: 0xABCD, preview: "预览文本")
    }

    /// **定位铁律**：书签持久化 JSON 不得含 pageIndex 字段。
    func testBookmarkHasNoPageIndex() throws {
        store.add(make(offset: 100))
        let data = try store.encodedJSON()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let keys = Set(json[0].keys)
        XCTAssertFalse(keys.contains("pageIndex"), "书签不得以 pageIndex 定位（定位铁律）")
        XCTAssertTrue(keys.contains("charOffset"))
        XCTAssertTrue(keys.contains("fingerprint"))
    }

    /// 同一锚点重复加只保留一条（防误触重复）。
    func testAddIsIdempotentOnSameAnchor() {
        store.add(make(offset: 100))
        store.add(make(offset: 100))
        XCTAssertEqual(store.allBookmarks().count, 1, "同一位置不应重复加书签")
    }

    /// 按章筛选并按偏移排序（供阅读器叠加显示）。
    func testChapterBookmarksSortedByOffset() {
        store.add(make(offset: 300))
        store.add(make(offset: 100))
        store.add(make(offset: 200))
        XCTAssertEqual(store.bookmarks(bookID: "b1", chapterID: 1).map(\.charOffset), [100, 200, 300])
    }

    /// 删除按锚点精确匹配。
    func testRemoveByAnchor() {
        store.add(make(offset: 100))
        store.add(make(offset: 200))
        store.remove(bookID: "b1", chapterID: 1, charOffset: 100)
        XCTAssertEqual(store.allBookmarks().count, 1)
    }

    /// 持久化往返（经 Persist 门面）。
    func testPersistRoundTrip() throws {
        store.add(make(offset: 42))
        try store.persist()

        let loaded = BookmarksStore(fileURL: store.fileURL)
        try loaded.load()
        let restored = try XCTUnwrap(loaded.allBookmarks().first)
        XCTAssertEqual(restored.charOffset, 42)
        XCTAssertEqual(restored.fingerprint, 0xABCD)
    }
}
