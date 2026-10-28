import Foundation
import SQLite3
import InkSightCore

// MARK: - LocalSearchStore（FR-024a 本地全文检索）

/// 本地全文检索仓库（FR-024a）：FTS5 索引**仅本地导入文件**的章节正文。
///
/// 契约（技术约束清单 FR-024a）：
/// - **索引对象仅本地导入文件**——在线书不索引（FR-024b：FTS 不索引在线正文）；
/// - **索引库设 `NSURLIsExcludedFromBackupKey`**（可重建，排除 iCloud 备份）；
/// - **万本级首屏 ≤1s**（FTS5 全文索引，非 LIKE 扫描）。
///
/// **中文分词方案**：`unicode61` tokenizer 对连续 CJK 字符整串分词（整句一个 token），
/// 多字查询永远不命中。解法：索引时逐字加空格（`characterSpaced`）使每个字独立 token；
/// 查询时逐字切分用 AND 连接（`characterMatch`）。
public final class LocalSearchStore: @unchecked Sendable {

    public static let defaultDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("InkSight/FTS", isDirectory: true)
    }()

    public let databaseURL: URL
    private var db: OpaquePointer?
    private let lock = NSLock()

    public init(databaseURL: URL = defaultDirectory.appendingPathComponent("search.db")) throws {
        self.databaseURL = databaseURL
        _ = Persist.prepareDirectory(for: databaseURL)

        let code = databaseURL.path.withCString { cpath in
            sqlite3_open_v2(cpath, &db,
                            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        }
        guard code == SQLITE_OK, db != nil else {
            throw SQLiteCacheError.openFailed(code)
        }
        try createSchema()
        // FR-024a：索引库排除备份（可重建）
        Persist.applyExcludedFromBackup(to: databaseURL)
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    /// 搜索命中项。
    public struct SearchHit: Equatable, Sendable {
        public let bookID: String
        public let bookTitle: String
        public let chapterIndex: Int
        /// 命中片段（FTS5 snippet，含上下文）。
        public let snippet: String
        /// 相关性分（FTS5 bm25，越小越相关）。
        public let rank: Double
    }

    // MARK: - 建表

    private func createSchema() throws {
        let sql = """
        CREATE VIRTUAL TABLE IF NOT EXISTS local_fts USING fts5(
            book_id UNINDEXED,
            book_title,
            chapter_index UNINDEXED,
            body,
            tokenize = 'unicode61'
        );
        """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteCacheError.stepFailed(sqlite3_errcode(db))
        }
    }

    // MARK: - 索引

    /// 索引一个章节（调用方负责切片正文，本仓库只消费文本）。
    public func indexChapter(bookID: String, bookTitle: String,
                             chapterIndex: Int, body: String) -> Result<Void, SQLiteCacheError> {
        lock.lock(); defer { lock.unlock() }
        guard let db else { return .failure(.openFailed(-1)) }
        let deleteSQL = "DELETE FROM local_fts WHERE book_id = ?1 AND chapter_index = ?2;"
        var delStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, deleteSQL, -1, &delStmt, nil) == SQLITE_OK else {
            return .failure(.prepareFailed(sqlite3_errcode(db)))
        }
        sqlite3_bind_text(delStmt, 1, bookID, -1, SQLiteCache.SQLITE_TRANSIENT)
        sqlite3_bind_int64(delStmt, 2, Int64(chapterIndex))
        let delRC = sqlite3_step(delStmt)
        sqlite3_finalize(delStmt)
        guard delRC == SQLITE_DONE else { return .failure(.stepFailed(delRC)) }

        let insertSQL = "INSERT INTO local_fts (book_id, book_title, chapter_index, body) VALUES (?, ?, ?, ?);"
        var insStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &insStmt, nil) == SQLITE_OK else {
            return .failure(.prepareFailed(sqlite3_errcode(db)))
        }
        sqlite3_bind_text(insStmt, 1, bookID, -1, SQLiteCache.SQLITE_TRANSIENT)
        sqlite3_bind_text(insStmt, 2, bookTitle, -1, SQLiteCache.SQLITE_TRANSIENT)
        sqlite3_bind_int64(insStmt, 3, Int64(chapterIndex))
        // **中文按字切分**：unicode61 对连续 CJK 整串分词，逐字加空格使每个字独立 token。
        sqlite3_bind_text(insStmt, 4, Self.characterSpaced(body), -1, SQLiteCache.SQLITE_TRANSIENT)
        let insRC = sqlite3_step(insStmt)
        sqlite3_finalize(insStmt)
        guard insRC == SQLITE_DONE else { return .failure(.stepFailed(insRC)) }
        return .success(())
    }

    /// **整书索引（FR-024a 完整闭环）**：从导入时的 `Data` ＋ 章节锚点逐章切片建索引。
    ///
    /// 与 `BookShelfStore` 的分工：
    /// - 导入（`BookShelfStore.importLocalBook`）求**快**——只扫描分章、取锚点，不解析正文；
    /// - 索引（本方法）求**可检索**——逐章切片喂 FTS，处理完一章即释放（不一次性全载）。
    ///
    /// 判据（NFR-08）：逐章切片、单章进索引后即释放；**不把全书正文同时驻留内存**。
    /// 返回成功索引的章节数。
    @discardableResult
    public func indexBook(bookID: String, bookTitle: String,
                          fileData: Data, chapters: [ChapterAnchor]) -> Int {
        var indexed = 0
        for (chapterIndex, anchor) in chapters.enumerated() {
            // 逐章切片（复用 BookShelfStore 的切片口径：字节范围 → UTF-8 文本）
            let end = min(anchor.byteOffset + anchor.byteLength, fileData.count)
            guard anchor.byteOffset <= end, end > anchor.byteOffset else { continue }
            let body = String(decoding: fileData[anchor.byteOffset..<end], as: UTF8.self)
            guard !body.isEmpty else { continue }
            if case .success = indexChapter(bookID: bookID, bookTitle: bookTitle,
                                            chapterIndex: chapterIndex, body: body) {
                indexed += 1
            }
        }
        return indexed
    }

    /// 删除一本书的全部索引（用户移除本地文件时调用）。
    public func removeBook(bookID: String) -> Result<Void, SQLiteCacheError> {
        lock.lock(); defer { lock.unlock() }
        guard let db else { return .failure(.openFailed(-1)) }
        let sql = "DELETE FROM local_fts WHERE book_id = ?1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return .failure(.prepareFailed(sqlite3_errcode(db)))
        }
        sqlite3_bind_text(stmt, 1, bookID, -1, SQLiteCache.SQLITE_TRANSIENT)
        let rc = sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        guard rc == SQLITE_DONE else { return .failure(.stepFailed(rc)) }
        return .success(())
    }

    // MARK: - 搜索

    /// 全文搜索（FTS5 MATCH）。`query` 为普通短语；限制条数上限。
    public func search(_ query: String, limit: Int = 50) -> [SearchHit] {
        lock.lock(); defer { lock.unlock() }
        guard let db, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let match = Self.characterMatch(query)
        guard !match.isEmpty else { return [] }

        let sql = """
        SELECT book_id, book_title, chapter_index,
               snippet(local_fts, 3, '…', '…', 12, 12) AS snip,
               bm25(local_fts) AS rank
        FROM local_fts WHERE local_fts MATCH ?1
        ORDER BY rank LIMIT ?2;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, match, -1, SQLiteCache.SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, Int64(limit))

        var hits: [SearchHit] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let bookID = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let bookTitle = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let chapterIndex = Int(sqlite3_column_int64(stmt, 2))
            let snippet = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
            let rank = sqlite3_column_double(stmt, 4)
            hits.append(SearchHit(bookID: bookID, bookTitle: bookTitle,
                                  chapterIndex: chapterIndex, snippet: snippet, rank: rank))
        }
        return hits
    }

    /// 已索引章节数（观测用）。
    public var indexedRowCount: Int {
        lock.lock(); defer { lock.unlock() }
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT count(*) FROM local_fts;", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    // MARK: - 中文按字切分（FTS5 unicode61 对 CJK 整串分词的解决方案）

    /// 把正文转成「逐字空格分隔」序列。
    static func characterSpaced(_ text: String) -> String {
        var out = ""
        for ch in text {
            if ch.isWhitespace || ch.isPunctuation || ch.isSymbol {
                out += " "
            } else {
                out += "\(ch) "
            }
        }
        return out
    }

    /// 把查询词转成 FTS5 MATCH 表达式：逐字切分 + AND 连接。
    static func characterMatch(_ query: String) -> String {
        var terms: [String] = []
        for word in query.split(whereSeparator: \.isWhitespace) {
            let w = String(word).replacingOccurrences(of: "\"", with: "")
            guard !w.isEmpty else { continue }
            if w.contains(where: { $0.isCJK }) {
                for ch in w where !ch.isPunctuation && !ch.isWhitespace {
                    terms.append("\"\(ch)\"")
                }
            } else {
                terms.append("\"\(w)\"")
            }
        }
        return terms.joined(separator: " AND ")
    }
}

// MARK: - CJK 判定辅助

extension Character {
    /// 是否 CJK 统一表意文字（中文全文检索逐字切分的判据）。
    var isCJK: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return (0x4E00...0x9FFF).contains(scalar.value)
            || (0x3400...0x4DBF).contains(scalar.value)
            || (0xF900...0xFAFF).contains(scalar.value)
    }
}
