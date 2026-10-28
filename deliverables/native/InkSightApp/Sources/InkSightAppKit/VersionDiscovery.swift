import Foundation
import InkSightCore

// MARK: - VersionDiscovery（FR-018 多副本发现）

/// 多副本发现：在书架里找出「同一本书的其它本地副本」，并算出它们的**位置匹配度**。
///
/// 判据（FR-018：指纹 ＝ 标题归一 ＋ 首尾 200 字哈希）：
/// - **同名**（书名归一后相等）视为候选；
/// - 匹配度按「首尾指纹命中数 / 2」＋ 章节数接近度加权，得到 0–1 的分；
/// - **不引入"源名"概念**——这里只有本地文件（PRD FR-018 明文）。
public enum VersionDiscovery {

    /// 首尾窗口（与 `VersionAlignmentEngine` 同源）。
    private static var window: Int { VersionAlignmentEngine.fingerprintWindow }

    /// 从书架里找出当前书的其它副本。
    ///
    /// - Parameters:
    ///   - current: 当前正在读的副本。
    ///   - shelf: 全部书架项。
    ///   - headTail: 取某书「首章首 200 字 + 末章末 200 字」的闭包（由调用方提供，
    ///     避免本类型直接读盘——保持纯逻辑可测）。
    public static func candidates(
        current: BookShelfItem,
        shelf: [BookShelfItem],
        headTail: (BookShelfItem) -> (head: String, tail: String)?
    ) -> [VersionCandidate] {
        let currentTitle = normalize(current.title)
        guard !currentTitle.isEmpty else { return [] }
        guard let currentSample = headTail(current) else { return [] }

        let currentHead = Fingerprint.fnv1a64(normalize(currentSample.head))
        let currentTail = Fingerprint.fnv1a64(normalize(currentSample.tail))

        var results: [VersionCandidate] = []
        for item in shelf where item.bookID != current.bookID {
            // 同名才考虑（本地同书多副本的最可靠线索）
            guard normalize(item.title) == currentTitle else { continue }
            guard let sample = headTail(item) else { continue }

            var score = 0.0
            if Fingerprint.fnv1a64(normalize(sample.head)) == currentHead { score += 0.5 }
            if Fingerprint.fnv1a64(normalize(sample.tail)) == currentTail { score += 0.5 }
            // 章节数接近度补正（内容被重切时首尾可能不齐，但章数通常相近）
            if item.chapterCount > 0, current.chapterCount > 0 {
                let ratio = Double(min(item.chapterCount, current.chapterCount))
                    / Double(max(item.chapterCount, current.chapterCount))
                score = min(1.0, score + ratio * 0.2)
            }

            results.append(VersionCandidate(
                id: item.bookID,
                fileName: item.fileURL?.lastPathComponent ?? item.title,
                versionLabel: VersionCandidate.defaultVersionLabel,
                fileSizeBytes: fileSize(item),
                format: (item.fileURL?.pathExtension ?? "txt").uppercased(),
                matchScore: min(1.0, score)
            ))
        }
        return VersionAlignmentEngine.ranked(results)
    }

    /// 文件大小（无 fileURL 时用章节数估算，**不伪造精确值**）。
    private static func fileSize(_ item: BookShelfItem) -> Int {
        if let url = item.fileURL,
           let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
           let size = values.fileSize {
            return size
        }
        // 无 fileURL：按章节数粗估（UI 会显示为 MB 量级，属估算）
        return max(0, item.chapterCount) * 4096
    }

    private static func normalize(_ text: String) -> String {
        VersionAlignmentEngine.normalize(text)
    }
}

// MARK: - VersionLabelStore（版本标签持久化）

/// 版本标签存储（FR-018：标签是**用户可编辑纯文本**，默认「未命名版本」，
/// 我方不预设任何值）。键为 bookID。
public final class VersionLabelStore: @unchecked Sendable {

    private var labels: [String: String] = [:]
    private let lock = NSLock()

    public static let defaultDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("com.inksight/versionlabels", isDirectory: true)
    }()

    public static let defaultFileName = "VersionLabels.json"

    public let fileURL: URL

    public init(fileURL: URL = defaultDirectory.appendingPathComponent(defaultFileName)) {
        self.fileURL = fileURL
        try? load()
    }

    /// 取标签；未设置返回 `nil`（由调用方回落到「未命名版本」）。
    public func label(for bookID: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return labels[bookID]
    }

    /// 设置标签（空串视为清除 → 回落默认「未命名版本」）。
    public func setLabel(_ label: String, for bookID: String) throws {
        lock.lock()
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { labels.removeValue(forKey: bookID) }
        else { labels[bookID] = trimmed }
        let snapshot = labels
        lock.unlock()
        try persist(snapshot)
    }

    private func persist(_ snapshot: [String: String]) throws {
        let data = try JSONEncoder().encode(snapshot)
        try Persist.write(data, to: fileURL, payload: .notes, excludedFromBackup: false).get()
    }

    private func load() throws {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        lock.lock(); defer { lock.unlock() }
        labels = decoded
    }
}
