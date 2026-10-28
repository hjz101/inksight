import Foundation
import InkSightCore

// MARK: - Bookmark（FR-011 书签）

/// 书签：**定位一律 `charOffset + fingerprint`**（定位铁律，与 `ReadingProgress`/`PageAnchor` 同源）。
///
/// - 结构上**没有 `pageIndex` 字段**（页码是渲染派生值，不落库——PRD FR-011 原文）；
/// - `charOffset`：书签起点（章节纯文本 UTF-16 偏移）；
/// - `fingerprint`：书签所在段落指纹（换文件/净化后对齐兜底）。
public struct Bookmark: Codable, Equatable, Hashable, Sendable {
    public let bookID: String
    public let chapterID: Int
    public let charOffset: Int
    public let fingerprint: UInt64
    /// 书签处的预览文本（展示快照；定位以 offset/fingerprint 为准）。
    public let preview: String
    public let createdAt: Date

    public init(bookID: String, chapterID: Int, charOffset: Int,
                fingerprint: UInt64, preview: String, createdAt: Date = Date()) {
        self.bookID = bookID
        self.chapterID = chapterID
        self.charOffset = charOffset
        self.fingerprint = fingerprint
        self.preview = preview
        self.createdAt = createdAt
    }
}

// MARK: - BookmarksStore（FR-011 持久化）

/// 书签仓库：持有全部书签，Codable JSON 落盘（经 `Persist` 单门，用户数据可备份）。
public final class BookmarksStore: @unchecked Sendable {

    private var bookmarks: [Bookmark] = []
    private let lock = NSLock()

    public static let defaultDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("com.inksight/bookmarks", isDirectory: true)
    }()

    public static let defaultFileName = "Bookmarks.json"

    public let fileURL: URL

    public init(fileURL: URL = defaultDirectory.appendingPathComponent(defaultFileName)) {
        self.fileURL = fileURL
    }

    public func add(_ bookmark: Bookmark) {
        lock.lock(); defer { lock.unlock() }
        // 同锚点幂等：重复加同一位置只保留最早一条（避免误触重复书签）
        if !bookmarks.contains(where: {
            $0.bookID == bookmark.bookID && $0.chapterID == bookmark.chapterID
                && $0.charOffset == bookmark.charOffset
        }) {
            bookmarks.append(bookmark)
        }
    }

    public func remove(bookID: String, chapterID: Int, charOffset: Int) {
        lock.lock(); defer { lock.unlock() }
        bookmarks.removeAll {
            $0.bookID == bookID && $0.chapterID == chapterID && $0.charOffset == charOffset
        }
    }

    /// FR-035 弃读清理：移除某书的全部书签。
    public func removeAll(bookID: String) {
        lock.lock(); defer { lock.unlock() }
        bookmarks.removeAll { $0.bookID == bookID }
    }

    public func allBookmarks() -> [Bookmark] {
        lock.lock(); defer { lock.unlock() }
        return bookmarks.sorted { $0.createdAt > $1.createdAt }
    }

    public func bookmarks(bookID: String, chapterID: Int) -> [Bookmark] {
        lock.lock(); defer { lock.unlock() }
        return bookmarks
            .filter { $0.bookID == bookID && $0.chapterID == chapterID }
            .sorted { $0.charOffset < $1.charOffset }
    }

    // MARK: - Codable 落盘（单门）

    public func encodedJSON() throws -> Data {
        lock.lock(); defer { lock.unlock() }
        return try JSONEncoder().encode(bookmarks)
    }

    public func persist() throws {
        let data = try encodedJSON()
        try Persist.write(data, to: fileURL, payload: .notes, excludedFromBackup: false).get()
    }

    public func load() throws {
        let data = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode([Bookmark].self, from: data)
        lock.lock(); defer { lock.unlock() }
        bookmarks = decoded
    }
}
