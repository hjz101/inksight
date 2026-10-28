import Foundation
import SQLite3
import InkSightCore

// MARK: - FR-024b 映射行（只存章节号/标题/偏移/首尾指纹，无正文）

/// FR-024b 在线进度映射行：**只存章节号、标题、字符偏移、首尾指纹哈希**，没有正文字段
/// （技术约束清单 FR-024b；表结构同此，`SQLiteCache` 的 `fr024b_mapping` 表即其落盘形态）。
public struct FR024bMapping: Equatable, Sendable {
    public let chapterID: Int
    public let title: String
    public let charOffset: Int
    public let startFingerprint: UInt64
    public let endFingerprint: UInt64

    public init(chapterID: Int, title: String, charOffset: Int,
                startFingerprint: UInt64, endFingerprint: UInt64) {
        self.chapterID = chapterID
        self.title = title
        self.charOffset = charOffset
        self.startFingerprint = startFingerprint
        self.endFingerprint = endFingerprint
    }
}

// MARK: - 错误

public enum SQLiteCacheError: Error, Equatable {
    case openFailed(Int32)
    case prepareFailed(Int32)
    case stepFailed(Int32)
    case quotaExceeded          // NFR-03：8MB 硬闸（预估已存负载字节超限即拒写）
}

// MARK: - SQLite 缓存层（NFR-03：8MB 硬闸；CTFrame 严禁落盘）

/// 本地缓存层（NFR-03：SQLite cache 8MB 硬闸）。
///
/// **落盘仅限结构元数据，绝不落正文：**
/// - `page_anchors`：分页锚点（chapterID / charOffset / charLength / lineCount / fingerprint），无正文；
/// - `chapter_anchors`：分章锚点（index / title / byteOffset / byteLength），无正文；
/// - `fr024b_mapping`：FR-024b 在线进度映射（章节号 / 标题 / 偏移 / 首尾指纹），无正文。
///
/// **CTFrame 严禁落盘**（合规四禁令：glyph＋字体可经反向 cmap 还原为 Unicode，视同正文）。
/// 本层 API 不接收、不存储任何 `CTFrame` 或正文字节流——结构层面进不来。
///
/// **8MB 硬闸**：以 Swift 层「预估已存负载字节」（保守高估）为判据；任一写入批次会使预估值
/// 越过 `maxCacheBytes` 即整批拒写并返回 `.quotaExceeded`，确保落盘文件永不逼近 8MB，
/// 且单测可确定性触发拒绝路径（不依赖 SQLite 内部页分配，避免非确定性）。
public final class SQLiteCache: @unchecked Sendable {

    public let databaseURL: URL
    public let maxCacheBytes: Int

    private var db: OpaquePointer?
    private var storedBytesEstimate: Int = 0
    private let lock = NSLock()

    /// `SQLITE_TRANSIENT`：绑定后 SQLite 立即拷贝数据，调用方缓冲区可释放。
    /// SQLITE_TRANSIENT：绑定后 SQLite 立即拷贝数据，调用方缓冲区可释放。
    /// internal：`LocalSearchStore`（FR-024a FTS）复用同一常量，避免两处各自定义。
    static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static let allowedTables = ["page_anchors", "chapter_anchors", "fr024b_mapping"]

    public init(databaseURL: URL, maxCacheBytes: Int = 8 * 1024 * 1024) throws {
        self.databaseURL = databaseURL
        self.maxCacheBytes = max(1, maxCacheBytes)

        // 建目录经 Persist 门面（E-04：所有写盘路径过门面；SQLite 以文件句柄打开，
        // 建目录这一步同样申报 payload 类型）
        _ = Persist.prepareDirectory(for: databaseURL)

        let code = databaseURL.path.withCString { cpath in
            sqlite3_open_v2(cpath, &db,
                            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        }
        guard code == SQLITE_OK, db != nil else {
            throw SQLiteCacheError.openFailed(code)
        }
        try applySchema()
        // 结构元数据（可重建）排除备份——经 Persist 门面统一出口
        Persist.applyExcludedFromBackup(to: databaseURL)
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - 写操作

    /// 写入分页锚点（PageAnchor 全字段均为结构元数据，无正文）。
    public func upsertPageAnchors(bookID: String, _ anchors: [PageAnchor]) -> Result<Void, SQLiteCacheError> {
        guard !anchors.isEmpty else { return .success(()) }
        return write(estimate: anchors.count * 64,
                     sql: """
                         INSERT OR REPLACE INTO page_anchors
                         (book_id, chapter_id, char_offset, char_length, line_count, fingerprint)
                         VALUES (?, ?, ?, ?, ?, ?);
                         """) { stmt in
            for a in anchors {
                sqlite3_bind_text(stmt, 1, bookID, -1, SQLiteCache.SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 2, Int64(a.chapterID))
                sqlite3_bind_int64(stmt, 3, Int64(a.charOffset))
                sqlite3_bind_int64(stmt, 4, Int64(a.charLength))
                sqlite3_bind_int64(stmt, 5, Int64(a.lineCount))
                sqlite3_bind_int64(stmt, 6, Int64(bitPattern: a.fingerprint))
                let rc = sqlite3_step(stmt)
                sqlite3_reset(stmt)
                if rc != SQLITE_DONE { return rc }   // 逐行失败上浮，不吞
            }
            return nil
        }
    }

    /// 写入分章锚点（ChapterAnchor：字节范围＋标题，无正文）。
    public func upsertChapterAnchors(bookID: String, _ chapters: [ChapterAnchor]) -> Result<Void, SQLiteCacheError> {
        guard !chapters.isEmpty else { return .success(()) }
        let estimate = chapters.reduce(0) { $0 + $1.title.utf8.count + 64 }
        return write(estimate: estimate,
                     sql: """
                         INSERT OR REPLACE INTO chapter_anchors
                         (book_id, chapter_index, title, byte_offset, byte_length)
                         VALUES (?, ?, ?, ?, ?);
                         """) { stmt in
            for c in chapters {
                sqlite3_bind_text(stmt, 1, bookID, -1, SQLiteCache.SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 2, Int64(c.index))
                sqlite3_bind_text(stmt, 3, c.title, -1, SQLiteCache.SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 4, Int64(c.byteOffset))
                sqlite3_bind_int64(stmt, 5, Int64(c.byteLength))
                let rc = sqlite3_step(stmt)
                sqlite3_reset(stmt)
                if rc != SQLITE_DONE { return rc }
            }
            return nil
        }
    }

    /// 写入 FR-024b 在线进度映射（章节号/标题/偏移/首尾指纹，无正文）。
    public func upsertFR024b(bookID: String, _ rows: [FR024bMapping]) -> Result<Void, SQLiteCacheError> {
        guard !rows.isEmpty else { return .success(()) }
        let estimate = rows.reduce(0) { $0 + $1.title.utf8.count + 128 }
        return write(estimate: estimate,
                     sql: """
                         INSERT OR REPLACE INTO fr024b_mapping
                         (book_id, chapter_id, title, char_offset, start_fingerprint, end_fingerprint)
                         VALUES (?, ?, ?, ?, ?, ?);
                         """) { stmt in
            for r in rows {
                sqlite3_bind_text(stmt, 1, bookID, -1, SQLiteCache.SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 2, Int64(r.chapterID))
                sqlite3_bind_text(stmt, 3, r.title, -1, SQLiteCache.SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 4, Int64(r.charOffset))
                sqlite3_bind_int64(stmt, 5, Int64(bitPattern: r.startFingerprint))
                sqlite3_bind_int64(stmt, 6, Int64(bitPattern: r.endFingerprint))
                let rc = sqlite3_step(stmt)
                sqlite3_reset(stmt)
                if rc != SQLITE_DONE { return rc }
            }
            return nil
        }
    }

    // MARK: - 观测（供契约测试）

    /// 读取表列名（白名单内才返回；供断言「无正文字段」）。
    public func columnNames(of table: String) -> [String] {
        guard SQLiteCache.allowedTables.contains(table) else { return [] }
        lock.lock(); defer { lock.unlock() }
        var names: [String] = []
        let sql = "PRAGMA table_info(\(table));"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else { return [] }
        defer { sqlite3_finalize(s) }
        while sqlite3_step(s) == SQLITE_ROW {
            if let c = sqlite3_column_text(s, 1) {
                names.append(String(cString: c))
            }
        }
        return names
    }

    /// 执行一条不走白名单的 DDL（**仅供测试构造真实故障场景**）。
    ///
    /// 生产代码不得调用——它绕过表白名单，存在的唯一理由是让契约测试能够
    /// 构造「表被删/结构损坏」这类无法从公开 API 触发的真实故障。
    func executeForTesting(_ sql: String) {
        lock.lock(); defer { lock.unlock() }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    /// 当前预估已存负载字节（硬闸判据，供测试断言）。
    public var currentStoredBytesEstimate: Int {
        lock.lock(); defer { lock.unlock() }
        return storedBytesEstimate
    }

    // MARK: - 内部

    /// 执行一批写操作。
    ///
    /// **本次两处修复（台账待编号）**：
    ///
    /// **① `sqlite3_step` 返回值被丢弃**：旧实现在闭包里裸调 `sqlite3_step(stmt)` 不看返回码，
    /// 于是主键冲突、约束失败、磁盘满等**逐行写入失败都会报 `.success`**——上层认为落盘成功，
    /// 实际数据没进去。现在收集逐行返回码，任一失败即整批返回 `.stepFailed` 且**不计入字节**。
    ///
    /// **② 配额计数器只增不减**：`storedBytesEstimate` 只在写入时累加，`INSERT OR REPLACE`
    /// 覆盖同一主键或删行时从不扣减，也不复位 → 反复重排同一本书会持续虚高，
    /// 最终**永久返回 `.quotaExceeded`**（缓存彻底不可写，只能重装 App）。
    /// 现在：估算逼近上限时用 SQLite 的真实页数（`page_count × page_size`）校正一次——
    /// 正常路径仍走廉价的估算累加（保持既有契约的精确语义），只有快要误判时才付真实统计的成本。
    private func write(estimate: Int, sql: String,
                       _ body: (OpaquePointer) -> Int32?) -> Result<Void, SQLiteCacheError> {
        lock.lock(); defer { lock.unlock() }

        // 估算逼近上限（≥80%）→ 用真实库大小校正，避免虚高导致永久拒写
        if storedBytesEstimate > maxCacheBytes * 4 / 5 {
            storedBytesEstimate = actualDatabaseBytesLocked()
        }

        // 8MB 硬闸：预估越限即整批拒写（不触碰 DB）
        guard storedBytesEstimate + estimate <= maxCacheBytes else {
            return .failure(.quotaExceeded)
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
            return .failure(.prepareFailed(sqlite3_errcode(db)))
        }
        defer { sqlite3_finalize(s) }
        // 逐行写入失败必须上浮，不能吞掉（否则「写成功」是假的）
        if let failure = body(s) {
            return .failure(.stepFailed(failure))
        }
        storedBytesEstimate += estimate
        return .success(())
    }

    /// 真实库大小（`page_count × page_size`），仅在校正时调用（持锁假设：调用方已持锁）。
    private func actualDatabaseBytesLocked() -> Int {
        var pageCount: Int64 = 0, pageSize: Int64 = 0
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA page_count;", -1, &stmt, nil) == SQLITE_OK, let s = stmt {
            if sqlite3_step(s) == SQLITE_ROW { pageCount = sqlite3_column_int64(s, 0) }
            sqlite3_finalize(s)
        }
        stmt = nil
        if sqlite3_prepare_v2(db, "PRAGMA page_size;", -1, &stmt, nil) == SQLITE_OK, let s = stmt {
            if sqlite3_step(s) == SQLITE_ROW { pageSize = sqlite3_column_int64(s, 0) }
            sqlite3_finalize(s)
        }
        return Int(pageCount * pageSize)
    }

    private func applySchema() throws {
        let stmts = [
            """
            CREATE TABLE IF NOT EXISTS page_anchors (
                book_id TEXT NOT NULL,
                chapter_id INTEGER NOT NULL,
                char_offset INTEGER NOT NULL,
                char_length INTEGER NOT NULL,
                line_count INTEGER NOT NULL,
                fingerprint INTEGER NOT NULL,
                PRIMARY KEY (book_id, chapter_id, char_offset)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS chapter_anchors (
                book_id TEXT NOT NULL,
                chapter_index INTEGER NOT NULL,
                title TEXT NOT NULL,
                byte_offset INTEGER NOT NULL,
                byte_length INTEGER NOT NULL,
                PRIMARY KEY (book_id, chapter_index)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS fr024b_mapping (
                book_id TEXT NOT NULL,
                chapter_id INTEGER NOT NULL,
                title TEXT NOT NULL,
                char_offset INTEGER NOT NULL,
                start_fingerprint INTEGER NOT NULL,
                end_fingerprint INTEGER NOT NULL,
                PRIMARY KEY (book_id, chapter_id)
            );
            """,
        ]
        for sql in stmts {
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                throw SQLiteCacheError.stepFailed(sqlite3_errcode(db))
            }
        }
    }
    // NFR-03 备份纪律（缓存库与目录排除 iCloud 备份）已上收至 `Persist.applyExcludedFromBackup`
    // ——落盘单门（E-04）要求所有写盘相关操作走同一出口，此处不再保有一份私有实现。
}
