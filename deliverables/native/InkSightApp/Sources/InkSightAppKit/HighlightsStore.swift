import Foundation
import InkSightCore

// MARK: - HighlightsStore（FR-013 划线/笔记仓库）

/// 划线/笔记仓库：持有全部划线，Codable JSON 落盘（经 `Persist` 单门）。
///
/// 纪律（与 `ReadingProgressStore` 同源）：
/// - **定位铁律**：锚点一律 `charOffset + length + fingerprint`，无 `pageIndex`；
/// - **无正文落盘**：只存划线元数据＋选中文本快照（用户自己选中的句子，非整章正文）；
/// - **可备份**：笔记属用户数据，`excludedFromBackup = false`（应随 iCloud 恢复）。
public final class HighlightsStore: @unchecked Sendable {

    private var highlights: [Highlight] = []
    private let lock = NSLock()

    /// 默认目录：`Application Support/com.inksight/highlights`。
    public static let defaultDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("com.inksight/highlights", isDirectory: true)
    }()

    public static let defaultFileName = "Highlights.json"

    public let fileURL: URL

    public init(fileURL: URL = defaultDirectory.appendingPathComponent(defaultFileName)) {
        self.fileURL = fileURL
    }
    // MARK: - 增删改查

    public func add(_ highlight: Highlight) {
        lock.lock(); defer { lock.unlock() }
        highlights.append(highlight)
    }

    public func remove(bookID: String, chapterID: Int, charOffset: Int) {
        lock.lock(); defer { lock.unlock() }
        highlights.removeAll {
            $0.bookID == bookID && $0.chapterID == chapterID && $0.charOffset == charOffset
        }
    }

    public func allHighlights() -> [Highlight] {
        lock.lock(); defer { lock.unlock() }
        return highlights.sorted { $0.createdAt > $1.createdAt }
    }

    /// 某书某章的全部划线（按偏移排序，供阅读器叠加显示）。
    public func highlights(bookID: String, chapterID: Int) -> [Highlight] {
        lock.lock(); defer { lock.unlock() }
        return highlights
            .filter { $0.bookID == bookID && $0.chapterID == chapterID }
            .sorted { $0.charOffset < $1.charOffset }
    }

    /// 按标签聚合（FR-013 标签；FR-022 一个标签跨书聚合的基础）。
    public func highlights(tag: String) -> [Highlight] {
        lock.lock(); defer { lock.unlock() }
        return highlights.filter { $0.tags.contains(tag) }
    }

    // MARK: - Codable 落盘（单门）

    public func encodedJSON() throws -> Data {
        lock.lock(); defer { lock.unlock() }
        return try JSONEncoder().encode(highlights)
    }

    /// 经 `Persist` 落盘单门原子写；笔记属用户数据，可备份。
    public func persist() throws {
        let data = try encodedJSON()
        let result = Persist.write(data, to: fileURL, payload: .notes, excludedFromBackup: false)
        try result.get()
    }

    public func load() throws {
        let data = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode([Highlight].self, from: data)
        lock.lock(); defer { lock.unlock() }
        highlights = decoded
    }
}
