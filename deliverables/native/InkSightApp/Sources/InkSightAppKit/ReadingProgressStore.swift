import Foundation
import InkSightCore

// MARK: - ReadingProgress（定位铁律的 Codable 落盘模型）

/// 阅读进度持久化模型（FR-024b 同源约束：定位一律 `charOffset + fingerprint`）。
///
/// 契约（原生阶段冻结项，写完不许静默改）：
/// - **只有 4 个字段**：`bookID` / `chapterID` / `charOffset` / `fingerprint`。
/// - **绝不可出现 `pageIndex` 字段**（定位铁律：页码是派生量，会漂移，落盘即埋雷）。
///   这是类型层保证，不是"约定不存"——`Codable` 输出也不可能有该键（见 ReadingProgressTests）。
/// - `fingerprint` 取 `PageAnchor.fingerprint` 同型 `UInt64`（页首段落归一化指纹）；
///   跨版本稳定，用于换文件/净化后 `charOffset` 越界时的对齐兜底。
public struct ReadingProgress: Codable, Equatable, Sendable {
    public let bookID: String
    public let chapterID: Int
    public let charOffset: Int
    public let fingerprint: UInt64

    public init(bookID: String, chapterID: Int, charOffset: Int, fingerprint: UInt64) {
        self.bookID = bookID
        self.chapterID = chapterID
        self.charOffset = charOffset
        self.fingerprint = fingerprint
    }
}

// MARK: - ReadingProgressStore（单门：只写 4 字段模型）

/// 进度仓库：持有各书最近阅读位置，并可由 Codable JSON 落盘/重载（4 字段，无 pageIndex）。
///
/// 与 `SQLiteCache` 的分工（避免双写冲突）：
/// - 本 store 存**跨会话续读进度**（每书一条），落盘为单份 JSON；
/// - `SQLiteCache` 存**分页/分章结构元数据**（PageAnchor/ChapterAnchor/FR-024b），无正文。
/// 两者都遵守定位铁律与「无正文落盘」；本 store 不触碰任何分页结构或 CTFrame。
public final class ReadingProgressStore: @unchecked Sendable {

    private var progresses: [String: ReadingProgress] = [:]
    private let lock = NSLock()

    public init() {}

    public func record(_ progress: ReadingProgress) {
        lock.lock(); defer { lock.unlock() }
        progresses[progress.bookID] = progress
    }

    public func progress(for bookID: String) -> ReadingProgress? {
        lock.lock(); defer { lock.unlock() }
        return progresses[bookID]
    }

    public var allBookIDs: [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(progresses.keys)
    }

    // MARK: - Codable 落盘（单门：仅 4 字段模型，不接触正文/分页）

    /// 将全部进度编码为一份 JSON（用于「导出 / 跨会话续读」；单门，见架构冻结版 E-04 同源纪律）。
    public func encodedJSON() throws -> Data {
        lock.lock(); defer { lock.unlock() }
        let snapshot = Array(progresses.values)
        return try JSONEncoder().encode(snapshot)
    }

    public func persist(to url: URL) throws {
        let data = try encodedJSON()
        // 落盘单门（E-04）：进度是用户数据，经 Persist 门面原子写。
        // 进度不设备份排除——跨会话续读进度应随 iCloud 恢复（同排版/动效偏好语义）。
        let result = Persist.write(data, to: url, payload: .readingProgress, excludedFromBackup: false)
        try result.get()
    }

    public func load(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode([ReadingProgress].self, from: data)
        lock.lock(); defer { lock.unlock() }
        for p in decoded { progresses[p.bookID] = p }
    }
}


// MARK: - 备份导出需要（FR-025：全量进度；同文件扩展可访问 private 存储）

extension ReadingProgressStore {
    /// 全量进度（供备份导出）。**只含 4 字段模型，无正文**。
    public func allProgress() -> [ReadingProgress] {
        lock.lock(); defer { lock.unlock() }
        return Array(progresses.values)
    }
}
