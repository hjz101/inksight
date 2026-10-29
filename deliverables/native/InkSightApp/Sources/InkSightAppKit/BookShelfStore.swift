import Foundation
import InkSightCore

// MARK: - 书源 / 书架项

public enum BookSource: String, Codable, Sendable {
    case localImport   // 用户本地导入文件
    case online        // 在线书（本期未接入拉取，仅占位登记）
}

/// 书架项：图书元信息 ＋ 最近阅读锚点（lastReadAnchor 即 `ReadingProgress`，4 字段，无 pageIndex）。
///
/// NFR-08 纪律：正文**永不随主表进内存**——本结构只存分章字节锚点 `[ChapterAnchor]` 与
/// 文件 `fileURL`，正文按需按字节范围切片（见 `BookShelfStore.chapterText(for:chapterIndex:)`）。
public struct BookShelfItem: Equatable, Sendable {
    public let bookID: String
    public let title: String
    /// FR-007 元数据：作者（导入时从文件名/OPF 解析，可手改）。
    public let author: String?
    /// FR-007 元数据：封面图字节（epub OPF 提取；nil ＝ 无封面 → 书架卡用配色占位）。
    public let coverImageData: Data?
    public let source: BookSource
    public let importDate: Date
    public let chapterCount: Int
    /// 本地导入文件路径（按需切片取章；正文不常驻内存）。
    public let fileURL: URL?
    /// 分章字节锚点（NFR-08：只存偏移/长度，不含正文）。
    public let chapters: [ChapterAnchor]
    public var lastReadAnchor: ReadingProgress?

    public init(bookID: String, title: String, author: String? = nil,
                coverImageData: Data? = nil,
                source: BookSource,
                importDate: Date, chapterCount: Int,
                fileURL: URL? = nil, chapters: [ChapterAnchor] = [],
                lastReadAnchor: ReadingProgress? = nil) {
        self.bookID = bookID
        self.title = title
        self.author = author
        self.coverImageData = coverImageData
        self.source = source
        self.importDate = importDate
        self.chapterCount = chapterCount
        self.fileURL = fileURL
        self.chapters = chapters
        self.lastReadAnchor = lastReadAnchor
    }
}

// MARK: - BookShelfStore（导入走 ChapterScanner.scan）

/// 书架仓库：图书元信息集合 ＋ 导入走 `ChapterScanner.scan`。
///
/// NFR-08 纪律：分章只产字节范围与标题，正文**永不随导入进内存**——
/// 导入时仅把原始 `Data` 交给 `ChapterScanner.scan` 取章节数，不在此解析正文。
public final class BookShelfStore: @unchecked Sendable {

    private(set) public var items: [BookShelfItem] = []
    private let lock = NSLock()

    public init() {}

    /// 导入本地文件（内存字节）：走 `ChapterScanner.scan` 取章节锚点（字节流扫描，正文不落内存），
    /// 登记为书架项。title 缺省时取首章标记或「未命名书籍」。
    /// - Parameters:
    ///   - bookID: 调用方给定的稳定 ID（本地导入＝文件名哈希或 UUID）。
    ///   - title: 展示书名（本地导入可取文件名）。
    ///   - fileData: 原始文件字节（仅扫描，不解析/不存储正文）。
    @discardableResult
    public func importLocalBook(bookID: String, title: String, fileData: Data) -> BookShelfItem {
        let result = ChapterScanner.scan(fileData)
        let metadata = MetadataParser.parseFromFileName(title)
        let displayTitle = title.isEmpty ? (result.chapters.first?.title ?? "未命名书籍") : metadata.title
        let item = BookShelfItem(
            bookID: bookID,
            title: displayTitle,
            author: metadata.author,
            source: .localImport,
            importDate: Date(),
            chapterCount: result.chapters.count,
            fileURL: nil,
            chapters: result.chapters
        )
        lock.lock(); defer { lock.unlock() }
        items.append(item)
        return item
    }

    /// 导入本地文件（文件路径）：读取 `Data` 仅用于扫描，随即释放（正文不常驻内存）；
    /// 章节字节锚点与 `fileURL` 入库，正文留待 `chapterText(for:chapterIndex:)` 按需切片。
    /// 读盘失败（如沙箱拒绝）抛错，调用方据此**不生成条目**（诚实空态，不伪装有书）。
    @discardableResult
    public func importLocalBook(bookID: String, title: String, fileURL: URL) throws -> BookShelfItem {
        let data = try Data(contentsOf: fileURL)
        // **FR-007：epub 走容器解包**（取 OPF 的 title/creator ＋ 封面）；
        // 非 epub 或解包失败 → 回落文件名推断（**不因解包失败阻断导入**）。
        var metadata = MetadataParser.parseFromFileName(fileURL.lastPathComponent)
        var cover: Data?
        // epub 需要先解包正文再分章：正文抽成纯文本后走既有 txt 链路，
        // **ChapterAnchor（字节偏移）契约一个字不改**。
        var contentURL = fileURL
        var contentData = data
        if fileURL.pathExtension.lowercased() == "epub" {
            if let extracted = try? EpubExtractor.extract(from: data) {
                if !extracted.metadata.title.isEmpty {
                    metadata.title = extracted.metadata.title
                }
                if let author = extracted.metadata.author, !author.isEmpty {
                    metadata.author = author
                }
                cover = extracted.metadata.coverImageData
            }
            // 正文提取 → 落本地缓存 txt（失败则保持原 epub，正文读不了但元数据仍可用）
            if let text = try? EpubTextExtractor.extract(from: data),
               let cached = try? Self.writeEpubTextCache(text.text, bookID: bookID) {
                contentURL = cached
                contentData = Data(text.text.utf8)
            }
        }
        // 用**最终内容**分章（epub 已换成提取出的纯文本）
        let result = ChapterScanner.scan(contentData)
        // **书名优先级（D-100 修正）**：
        // ① 调用方显式传的 title；② **元数据解析出的书名**（文件名/OPF）；
        // ③ 首章标题；④ 兜底。
        // 此前把 ③ 排在 ② 前面，导致 epub 解包出的书名被"未命名章节"覆盖
        // （zip 字节过章扫描器扫不出章节，只得默认名）。
        let displayTitle: String = {
            if !title.isEmpty { return metadata.title.isEmpty ? title : metadata.title }
            if !metadata.title.isEmpty { return metadata.title }
            return result.chapters.first?.title ?? "未命名书籍"
        }()
        let item = BookShelfItem(
            bookID: bookID,
            title: displayTitle,
            author: metadata.author,
            coverImageData: cover,
            source: .localImport,
            importDate: Date(),
            chapterCount: result.chapters.count,
            fileURL: contentURL,
            chapters: result.chapters
        )
        lock.lock(); defer { lock.unlock() }
        items.append(item)
        return item
    }

    /// epub 正文缓存目录（`Caches/InkSight/EpubText`）。
    ///
    /// **放 Caches 而非 Application Support**：这是可重建的派生数据
    /// （原文 epub 仍在用户手里），丢了下次导入即可重建；
    /// 且按 NFR 缓存目录纪律需设 `NSURLIsExcludedFromBackupKey`。
    public static func epubTextCacheURL(bookID: String) throws -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("InkSight/EpubText", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // bookID 可能含文件名特殊字符 → 用稳定哈希做文件名
        let name = String(format: "%016llx", Fingerprint.fnv1a64(bookID))
        return dir.appendingPathComponent("\(name).txt")
    }

    /// 写 epub 正文缓存（带备份排除）。
    static func writeEpubTextCache(_ text: String, bookID: String) throws -> URL {
        let url = try epubTextCacheURL(bookID: bookID)
        // 用 `structuralMetadata`（定义即"可重建，排除 iCloud 备份"）——
        // epub 正文缓存属派生数据，不是用户原始资产。
        try Persist.write(Data(text.utf8), to: url, payload: .structuralMetadata,
                          excludedFromBackup: true).get()
        return url
    }

    /// 按需切片取章：仅按 `ChapterAnchor` 的字节范围从磁盘读**单章**正文（NFR-08：正文不常驻内存，
    /// 会话内存 ≤3 章）。无 `fileURL` 或越界返回 nil。
    public func chapterText(for item: BookShelfItem, chapterIndex: Int) -> String? {
        guard let url = item.fileURL,
              chapterIndex >= 0, chapterIndex < item.chapters.count else { return nil }
        let anchor = item.chapters[chapterIndex]
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        let total = Int(fh.seekToEndOfFile())
        guard anchor.byteOffset < total else { return nil }
        let length = min(anchor.byteLength, total - anchor.byteOffset)
        guard length > 0 else { return nil }
        try? fh.seek(toOffset: UInt64(anchor.byteOffset))
        let sub = fh.readData(ofLength: length)
        return String(decoding: sub, as: UTF8.self)
    }

    /// 内存夹具切片：给定 `Data` 与 `ChapterAnchor`，切出章节纯文本（测试/无文件场景用）。
    public static func sliceChapter(from data: Data, anchor: ChapterAnchor) -> String {
        let end = min(anchor.byteOffset + anchor.byteLength, data.count)
        guard anchor.byteOffset <= end else { return "" }
        return String(decoding: data[anchor.byteOffset..<end], as: UTF8.self)
    }

    /// 记录阅读进度：更新对应书架项的 `lastReadAnchor`（定位铁律，4 字段，无 pageIndex）。
    public func recordProgress(_ progress: ReadingProgress) {
        lock.lock(); defer { lock.unlock() }
        guard let idx = items.firstIndex(where: { $0.bookID == progress.bookID }) else { return }
        var item = items[idx]
        item.lastReadAnchor = progress
        items[idx] = item
    }

    public func item(for bookID: String) -> BookShelfItem? {
        lock.lock(); defer { lock.unlock() }
        return items.first(where: { $0.bookID == bookID })
    }

    /// **当前书**（继续阅读优先）：有 `lastReadAnchor` 的那本优先，否则取第一本。
    /// 无书返回 nil（调用方须走**诚实空态**，不伪造书目）。
    ///
    /// 开发包 #8：设置页的「重排当前章」据此定位真实书。
    public var currentItem: BookShelfItem? {
        lock.lock(); defer { lock.unlock() }
        return items.first(where: { $0.lastReadAnchor != nil }) ?? items.first
    }
}

// MARK: - FR-035 手动弃读

extension BookShelfStore {
    /// 手动弃读（FR-035）：从书架移除该书并清理全部关联数据。
    ///
    /// **必须同时清理（否则就是"幽灵书"——条目没了，数据还在）**：
    /// - 阅读进度（`ReadingProgressStore`）；
    /// - 书签（`BookmarksStore`）；
    /// - 划线/笔记（`HighlightsStore`）；
    /// - 本地检索索引（`LocalSearchStore`，按 bookID 移除）；
    /// - 版本标签（`VersionLabelStore`）。
    ///
    /// - Returns: 是否实际移除（无此书返回 false）。
    @discardableResult
    public func abandon(bookID: String,
                        progressStore: ReadingProgressStore? = nil,
                        bookmarksStore: BookmarksStore? = nil,
                        highlightsStore: HighlightsStore? = nil,
                        searchStore: LocalSearchStore? = nil,
                        labelStore: VersionLabelStore? = nil) -> Bool {
        lock.lock()
        guard let idx = items.firstIndex(where: { $0.bookID == bookID }) else {
            lock.unlock()
            return false
        }
        items.remove(at: idx)
        lock.unlock()

        // 清理关联数据（在锁外执行，避免死锁——各 store 有自己的锁）
        progressStore?.clear(bookID: bookID)
        bookmarksStore?.removeAll(bookID: bookID)
        highlightsStore?.removeAll(bookID: bookID)
        searchStore?.removeBook(bookID: bookID)
        try? labelStore?.remove(bookID: bookID)
        return true
    }
}
