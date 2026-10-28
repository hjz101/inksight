import XCTest
@testable import InkSightAppKit
import InkSightCore
import Foundation

/// SQLite 缓存层契约测试（开发包 #3）。
///
/// 四项契约：
/// ① 表结构**无正文字段**（FR-024b：只存结构元数据）；
/// ② 缓存库与目录均设 `NSURLIsExcludedFromBackupKey`（NFR-03 备份纪律）；
/// ③ 8MB 硬闸（NFR-03）：预估负载越限整批拒写，返回 `.quotaExceeded`；
/// ④（联动 ①）列名白名单恰好等于预期，反向断言禁止任何正文似名列。
final class SQLiteCacheTests: XCTestCase {

    var cache: SQLiteCache!
    var dbURL: URL!

    override func setUp() {
        super.setUp()
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        dbURL = parent.appendingPathComponent("cache.db")
        cache = try! SQLiteCache(databaseURL: dbURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dbURL)
        cache = nil
        super.tearDown()
    }

    /// 契约①②：三张表列名白名单恰好为预期，且不含任何正文字段。
    func testSchemaHasNoBodyColumns() {
        let expected: [String: Set<String>] = [
            "page_anchors":     ["book_id", "chapter_id", "char_offset", "char_length", "line_count", "fingerprint"],
            "chapter_anchors": ["book_id", "chapter_index", "title", "byte_offset", "byte_length"],
            "fr024b_mapping":  ["book_id", "chapter_id", "title", "char_offset", "start_fingerprint", "end_fingerprint"],
        ]
        let forbidden = ["body", "content", "text", "chapter_text", "paragraph", "raw", "body_text", "chapter_body"]
        for (table, cols) in expected {
            let got = Set(cache.columnNames(of: table))
            XCTAssertEqual(got, cols, "表 \(table) 列名必须恰好为白名单，不得含正文字段")
            XCTAssertFalse(got.contains(where: { forbidden.contains($0) }),
                           "表 \(table) 不得含正文字段（FR-024b：表结构里没有正文字段）")
        }
        // 非白名单表名不得泄露列（防御性）
        XCTAssertEqual(cache.columnNames(of: "sqlite_master"), [])
    }

    /// 契约③：缓存库与所在目录均排除 iCloud 备份。
    func testExcludedFromBackup() throws {
        let fileValues = try dbURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(fileValues.isExcludedFromBackup, true, "DB 文件必须排除 iCloud 备份")

        let dirURL = dbURL.deletingLastPathComponent()
        let dirValues = try dirURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(dirValues.isExcludedFromBackup, true, "缓存目录必须排除 iCloud 备份")
    }

    /// 契约④：8MB 硬闸——预估已存负载字节越限即整批拒写，返回 .quotaExceeded，且不计入已存字节。
    func testQuotaExceededRejectsWrite() throws {
        // 极小 cap，使一批 chapter_anchors 的预估负载越限
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-quota-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let tinyURL = parent.appendingPathComponent("cache.db")
        defer { try? FileManager.default.removeItem(at: parent) }

        let capped = try SQLiteCache(databaseURL: tinyURL, maxCacheBytes: 1024)

        let chapters = (0..<20).map {
            ChapterAnchor(index: $0,
                         title: "第\($0)章 一段不算短的章节标题用于撑满配额测试",
                         byteOffset: $0 * 100, byteLength: 100)
        }
        let result = capped.upsertChapterAnchors(bookID: "b", chapters)
        // Result<Void,...> 在本工具链不具 Equatable（Void 不满足条件遵循），改用 get() 抛错判定
        XCTAssertThrowsError(try result.get(), "越限批次必须被硬闸拒写") { err in
            guard let e = err as? SQLiteCacheError else { return XCTFail("期望 SQLiteCacheError，实际 \(err)") }
            XCTAssertEqual(e, .quotaExceeded)
        }
        XCTAssertEqual(capped.currentStoredBytesEstimate, 0, "被拒批次不得计入已存字节")

        // 对照：默认 8MB cap 下同一批被接受
        let ok = cache.upsertChapterAnchors(bookID: "b", chapters)
        XCTAssertNoThrow(try ok.get(), "默认 8MB cap 下应接受该批")
    }

    /// 联动：page_anchors 正常写入（无正文），预估字节按固定行宽计入。
    func testUpsertPageAnchorsRoundTrip() {
        let anchors = [
            PageAnchor(chapterID: 1, charOffset: 0,   charLength: 100, lineCount: 5, fingerprint: 12345),
            PageAnchor(chapterID: 1, charOffset: 100, charLength: 80,  lineCount: 4, fingerprint: 67890),
        ]
        let r = cache.upsertPageAnchors(bookID: "b", anchors)
        XCTAssertNoThrow(try r.get())
        XCTAssertEqual(cache.currentStoredBytesEstimate, anchors.count * 64)
    }

    /// 联动：FR-024b 映射行写入（只章节号/标题/偏移/首尾指纹，无正文）。
    func testFr024bMappingNoBodyWrite() {
        let rows = [FR024bMapping(chapterID: 1, title: "第1章 起始",
                                  charOffset: 0, startFingerprint: 111, endFingerprint: 222)]
        let r = cache.upsertFR024b(bookID: "b", rows)
        XCTAssertNoThrow(try r.get())
    }

    /// 防御：空批次直接成功、不触闸、不计入字节。
    func testEmptyBatchIsNoOp() {
        XCTAssertNoThrow(try cache.upsertPageAnchors(bookID: "b", []).get())
        XCTAssertNoThrow(try cache.upsertChapterAnchors(bookID: "b", []).get())
        XCTAssertNoThrow(try cache.upsertFR024b(bookID: "b", []).get())
        XCTAssertEqual(cache.currentStoredBytesEstimate, 0)
    }
}
