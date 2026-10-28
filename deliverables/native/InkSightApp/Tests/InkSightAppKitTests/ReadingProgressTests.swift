import XCTest
@testable import InkSightAppKit
import Foundation

/// 定位铁律的 Codable 契约测试（模仿 InkSightCore PageAnchor 测试 ⑥）：
/// `ReadingProgress` 的 JSON 编码**恰好只有 4 个键**，且**绝不含 `pageIndex`**。
final class ReadingProgressTests: XCTestCase {

    /// 契约①：编码键恰好为 4 个，且不含 pageIndex（模仿 InkSightCore PageAnchor 测试 ⑥ 的 JSON 键断言）。
    func testCodableHasExactlyFourKeysAndNoPageIndex() throws {
        let progress = ReadingProgress(
            bookID: "book-1", chapterID: 3, charOffset: 1024, fingerprint: 0x9e3779b97f4a7c15
        )
        let data = try JSONEncoder().encode(progress)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let keys = Set(obj.keys)
        XCTAssertEqual(keys, ["bookID", "chapterID", "charOffset", "fingerprint"],
                       "ReadingProgress 编码键必须恰好是 4 个，不得多不得少")
        XCTAssertFalse(keys.contains("pageIndex"),
                       "定位铁律：ReadingProgress 不得出现 pageIndex 字段（页码是派生量，落盘即埋雷）")

        // 类型正确 + 值无损耗：用 JSONDecoder 回解（fingerprint 为 UInt64，超 Int 范围，故不走 is Int 判定）
        let decoded = try JSONDecoder().decode(ReadingProgress.self, from: data)
        XCTAssertEqual(decoded.bookID, "book-1")
        XCTAssertEqual(decoded.chapterID, 3)
        XCTAssertEqual(decoded.charOffset, 1024)
        XCTAssertEqual(decoded.fingerprint, 0x9e3779b97f4a7c15)
        XCTAssertEqual(decoded.fingerprint, progress.fingerprint, "UInt64 指纹不得因 JSON 往返丢精度")
    }

    /// Codable 往返：4 字段无损耗，无 pageIndex 泄漏。
    func testRoundTripViaJSON() throws {
        let store = ReadingProgressStore()
        store.record(ReadingProgress(bookID: "b1", chapterID: 1, charOffset: 10, fingerprint: 111))
        store.record(ReadingProgress(bookID: "b2", chapterID: 2, charOffset: 20, fingerprint: 222))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-progress-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try store.persist(to: url)
        let reloaded = ReadingProgressStore()
        try reloaded.load(from: url)

        XCTAssertEqual(reloaded.progress(for: "b1")?.charOffset, 10)
        XCTAssertEqual(reloaded.progress(for: "b2")?.fingerprint, 222)

        // 落盘 JSON 再次断言无 pageIndex
        let raw = try Data(contentsOf: url)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [[String: Any]])
        for entry in obj {
            XCTAssertFalse(Set(entry.keys).contains("pageIndex"),
                           "落盘 JSON 中不得出现 pageIndex")
        }
    }

    /// 书架导入走 `ChapterScanner.scan`：字节流分章，正文不进内存，输出章节数。
    func testBookShelfImportUsesChapterScanner() {
        let text = "第1章 起始\n正文一\n第2章 发展\n正文二\n第3章 尾声\n正文三\n"
        let data = Data(text.utf8)
        let store = BookShelfStore()
        let item = store.importLocalBook(bookID: "demo", title: "演示书", fileData: data)

        XCTAssertEqual(item.chapterCount, 3, "导入应走 ChapterScanner.scan 得到 3 章")
        XCTAssertEqual(item.source, .localImport)
        XCTAssertNil(item.lastReadAnchor, "新书无阅读锚点")
        XCTAssertEqual(store.item(for: "demo")?.bookID, "demo")
    }

    /// 记录进度写入 lastReadAnchor（4 字段，无 pageIndex）。
    func testRecordProgressUpdatesLastReadAnchor() {
        let store = BookShelfStore()
        let item = store.importLocalBook(bookID: "b", title: "书", fileData: Data("第1章 一\n内容\n".utf8))
        let progress = ReadingProgress(bookID: "b", chapterID: 1, charOffset: 5, fingerprint: 999)
        store.recordProgress(progress)

        let updated = store.item(for: "b")
        XCTAssertEqual(updated?.lastReadAnchor?.charOffset, 5)
        XCTAssertEqual(updated?.lastReadAnchor?.chapterID, 1)
        XCTAssertEqual(updated?.bookID, item.bookID)
    }
}
