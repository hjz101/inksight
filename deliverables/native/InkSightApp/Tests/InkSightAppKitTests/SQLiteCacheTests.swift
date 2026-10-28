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

    // MARK: - 本次修复的回归测试（台账待编号）

    /// **回归①：反复覆盖写同一主键不得让配额计数器虚高**。
    ///
    /// 历史缺陷：`storedBytesEstimate` 只增不减，`INSERT OR REPLACE` 覆盖时也照加，
    /// 反复重排同一本书会让估算持续膨胀，最终**永久返回 `.quotaExceeded`**（缓存不可写）。
    func testRepeatedOverwriteDoesNotInflateQuota() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-overwrite-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let url = parent.appendingPathComponent("cache.db")

        // cap 取 64KB：若计数器单调累加，50 次覆盖写会耗尽
        let capped = try SQLiteCache(databaseURL: url, maxCacheBytes: 64 * 1024)
        let anchors = (0..<10).map {
            PageAnchor(chapterID: 1, charOffset: $0 * 100, charLength: 100,
                       lineCount: 5, fingerprint: UInt64($0))
        }
        // 同一批锚点反复覆盖 50 次（模拟反复重排同一章）
        for _ in 0..<50 {
            XCTAssertNoThrow(try capped.upsertPageAnchors(bookID: "b", anchors).get(),
                             "覆盖写不得因配额虚高被拒")
        }
        XCTAssertLessThanOrEqual(capped.currentStoredBytesEstimate, 64 * 1024,
                                 "反复覆盖后估算不得越限")
    }

    /// **回归②：逐行写入失败必须上浮，不能报 `.success`**。
    ///
    /// 历史缺陷：闭包里裸调 `sqlite3_step(stmt)` 丢弃返回码——主键冲突、约束失败、
    /// 表被删等逐行失败全部被吞，上层拿到 `.success` 却什么都没写进去。
    ///
    /// 构造方式：**先 DROP 掉目标表**，此后 INSERT 必然以 `SQLITE_ERROR` 失败。
    /// （注：只读文件不构成本测试的有效构造——SQLite 用目录级锁，只读属主文件仍可写。）
    func testStepFailureIsNotSwallowed() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-stepfail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let url = parent.appendingPathComponent("cache.db")
        let cache = try SQLiteCache(databaseURL: url)

        // 对照组：表存在时正常成功
        let ok = cache.upsertPageAnchors(bookID: "b", [
            PageAnchor(chapterID: 1, charOffset: 0, charLength: 10, lineCount: 1, fingerprint: 1)
        ])
        XCTAssertNoThrow(try ok.get(), "对照组：表存在时应成功")

        // 用 cache 自己的连接把表删掉（模拟"表不见了"这类真实故障）
        cache.executeForTesting("DROP TABLE page_anchors;")

        let failed = cache.upsertPageAnchors(bookID: "b", [
            PageAnchor(chapterID: 2, charOffset: 0, charLength: 10, lineCount: 1, fingerprint: 2)
        ])
        var threw = false
        do {
            try failed.get()
        } catch {
            threw = true
        }
        XCTAssertTrue(threw, "表不存在时的写入必须上浮为错误；报 .success 说明 step 返回码仍被吞掉")
    }
}
