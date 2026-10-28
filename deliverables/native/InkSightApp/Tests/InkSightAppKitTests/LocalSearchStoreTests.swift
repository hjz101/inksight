import XCTest
@testable import InkSightAppKit
import InkSightCore

/// FR-024a 本地全文检索契约测试。
final class LocalSearchStoreTests: XCTestCase {

    private var tempDir: URL!
    private var store: LocalSearchStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-fts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = try LocalSearchStore(databaseURL: tempDir.appendingPathComponent("search.db"))
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    /// 索引章节后能被全文检索命中，且返回书/章定位与片段。
    func testIndexThenSearchHits() throws {
        let body = "墨见读书专注本地阅读，支持自定义字号行高与边距，严守定位铁律只以字符偏移恢复进度。"
        XCTAssertNoThrow(try store.indexChapter(bookID: "b1", bookTitle: "测试书",
                                                chapterIndex: 3, body: body).get())

        let hits = store.search("定位铁律")
        XCTAssertEqual(hits.count, 1, "应命中 1 条")
        XCTAssertEqual(hits[0].bookID, "b1")
        XCTAssertEqual(hits[0].bookTitle, "测试书")
        XCTAssertEqual(hits[0].chapterIndex, 3)
        // snippet 是逐字空格 token 序列（"定 位 铁 律"），命中字被 '…' 标记包裹。
        // 断言片段非空且含首个命中字「定」（FTS5 标记命中 token 的固有形态）。
        XCTAssertFalse(hits[0].snippet.isEmpty, "片段不应为空")
        XCTAssertTrue(hits[0].snippet.contains("定"), "片段应含命中字「定」，实际：\(hits[0].snippet)")
    }

    /// 未命中词返回空。
    func testSearchNoMatch() throws {
        XCTAssertNoThrow(try store.indexChapter(bookID: "b1", bookTitle: "测试书",
                                                chapterIndex: 0, body: "只有这句正文。").get())
        XCTAssertTrue(store.search("不存在的词xyz").isEmpty)
    }

    /// 幂等覆盖：重复索引同 (bookID, chapterIndex) 覆盖旧内容（不产生重复行）。
    func testReindexIsIdempotent() throws {
        XCTAssertNoThrow(try store.indexChapter(bookID: "b1", bookTitle: "测试书",
                                                chapterIndex: 0, body: "旧内容甲").get())
        XCTAssertNoThrow(try store.indexChapter(bookID: "b1", bookTitle: "测试书",
                                                chapterIndex: 0, body: "新内容乙").get())
        XCTAssertEqual(store.indexedRowCount, 1, "重复索引不得产生重复行")
        XCTAssertTrue(store.search("新内容乙").count == 1)
        XCTAssertTrue(store.search("旧内容甲").isEmpty, "旧内容必须被覆盖")
    }

    /// 移除整本书的索引。
    func testRemoveBook() throws {
        XCTAssertNoThrow(try store.indexChapter(bookID: "b1", bookTitle: "A", chapterIndex: 0, body: "内容一").get())
        XCTAssertNoThrow(try store.indexChapter(bookID: "b2", bookTitle: "B", chapterIndex: 0, body: "内容二").get())
        XCTAssertEqual(store.indexedRowCount, 2)
        XCTAssertNoThrow(try store.removeBook(bookID: "b1").get())
        XCTAssertEqual(store.indexedRowCount, 1, "移除 b1 后只剩 b2")
        XCTAssertTrue(store.search("内容一").isEmpty)
        XCTAssertEqual(store.search("内容二").count, 1)
    }

    /// **索引库排除备份**（FR-024a：`NSURLIsExcludedFromBackupKey`）。
    func testIndexExcludedFromBackup() throws {
        let values = try store.databaseURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true,
                       "FTS 索引库必须排除 iCloud 备份（可重建数据）")
    }

    /// 空查询 / 全空白查询返回空（不触发 FTS5 语法错误）。
    func testEmptyQuerySafe() throws {
        XCTAssertNoThrow(try store.indexChapter(bookID: "b1", bookTitle: "A", chapterIndex: 0, body: "内容").get())
        XCTAssertTrue(store.search("").isEmpty)
        XCTAssertTrue(store.search("   ").isEmpty)
    }

    /// 多词查询按 AND 匹配（FTS5 默认 OR，但本实现转 AND——用户多词意图是"都出现"）。
    func testMultiTermQueryIsAnd() throws {
        XCTAssertNoThrow(try store.indexChapter(bookID: "b1", bookTitle: "A", chapterIndex: 0,
                                                body: "定位铁律与合规四禁令。").get())
        XCTAssertNoThrow(try store.indexChapter(bookID: "b2", bookTitle: "B", chapterIndex: 0,
                                                body: "定位铁律但不含四禁令。").get())
        // 两个词都出现的只有 b1
        let hits = store.search("定位铁律 合规")
        XCTAssertEqual(hits.map(\.bookID), ["b1"], "多词 AND 匹配应只命中 b1")
    }

    // MARK: - 整书索引闭环（FR-024a：导入 → 索引 → 可检索）

    /// 从导入的 `Data` + 章节锚点整书索引后，可跨章检索。
    func testIndexBookFromImportedData() throws {
        // 造两章内容
        let ch1 = "第一章 开头\n这是第一章的正文内容，包含关键词定位铁律。"
        let ch2 = "第二章 继续\n这是第二章的正文内容，也提到定位铁律与字符偏移。"
        let full = ch1 + "\n" + ch2
        let data = Data(full.utf8)
        let scan = ChapterScanner.scan(data)

        let indexed = store.indexBook(bookID: "book-1", bookTitle: "两章书",
                                      fileData: data, chapters: scan.chapters)
        XCTAssertGreaterThan(indexed, 0, "应至少索引 1 章")

        let hits = store.search("定位铁律")
        XCTAssertFalse(hits.isEmpty, "整书索引后应能检索到关键词")
        XCTAssertTrue(hits.allSatisfy { $0.bookID == "book-1" })
    }

    /// 整书索引逐章切片：章节数与扫描锚点一致，且不一次性全载（构造保证，此处验证索引行数）。
    func testIndexBookIndexesAllChapters() throws {
        let chapterBody = "这是一个用于验证整书索引的章节正文，包含足够长度以形成独立章节。"
        let full = (0..<5).map { "第\($0)章 标题\n\(chapterBody)" }.joined(separator: "\n")
        let data = Data(full.utf8)
        let scan = ChapterScanner.scan(data)

        let indexed = store.indexBook(bookID: "book-5", bookTitle: "五章书",
                                      fileData: data, chapters: scan.chapters)
        XCTAssertEqual(indexed, scan.chapters.count, "每章都应被索引")
        XCTAssertEqual(store.indexedRowCount, scan.chapters.count, "索引行数应等于章节数")
    }
}
