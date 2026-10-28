import Foundation
import InkSightCore

// MARK: - TypographyPresetStore（开发包 #6 · 持久化排版预设）

/// 排版预设持久化（开发包 #6）：单门 JSON 落盘当前 `ReaderTypography`。
///
/// 设计要点（与既有纪律同源）：
/// - 复用 `ReadingProgressStore` 的 `encodedJSON / persist(to:) / load(from:)` 原子写 `[.atomic]` 模式
///   （架构冻结版 E-04 单门纪律：一份 JSON、一个文件、一个语义）。
/// - **不设 `NSURLIsExcludedFromBackupKey`**：用户排版偏好应可备份——与 SQLiteCache 8MB 硬闸相反，
///   SQLiteCache 存的是「可重建」的分页结构元数据，而排版预设是用户偏好，丢备份即丢设置。
/// - 默认路径：`Application Support/com.inksight/preset/TypographyPreset.json`。
/// - Codable 只 8 字段（即 `ReaderTypography` 自身），**无 pageIndex、无正文**：定位铁律同源
///   （进度只 `charOffset + fingerprint`，预设与分页/进度数据互不耦合）。
///
/// 严守铁律：
/// - 本 store 只碰 `ReaderTypography`，不触碰 `PageAnchor` / `CTFrame` / 正文，不触发任何分页或重排；
/// - 0 玻璃（数据层，不涉及 SwiftUI）。
public final class TypographyPresetStore: @unchecked Sendable {

    /// 默认目录：`Application Support/com.inksight/preset`。
    public static let defaultDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("com.inksight/preset", isDirectory: true)
    }()

    public static let defaultFileName = "TypographyPreset.json"

    public let fileURL: URL

    /// - Parameter fileURL: 落盘路径；默认 `defaultDirectory/defaultFileName`。
    public init(fileURL: URL = defaultDirectory.appendingPathComponent(defaultFileName)) {
        self.fileURL = fileURL
    }

    /// 读取当前预设。
    ///
    /// 诚实回退：无文件 / 解码失败 / 读取异常均返回 `ReaderTypography.default`，
    /// **不抛错、不伪造**（骨架页纪律同源——空态不伪装成有内容）。
    public func load() -> ReaderTypography {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .default }
        guard let data = try? Data(contentsOf: fileURL) else { return .default }
        guard let decoded = try? JSONDecoder().decode(ReaderTypography.self, from: data) else { return .default }
        // **档位归一化（FR-009）**：旧设置页用滑块可写出 14…28pt 等越界值；
        // 读入时压回合法档位，防止历史非法值继续生效（normalize 幂等，合法值不变）。
        return TypographyTiers.normalize(decoded)
    }

    /// 持久化预设：经 `Persist` 落盘单门（E-04）原子写。
    ///
    /// 注意：**不设 `NSURLIsExcludedFromBackupKey`**——用户偏好应可随 iCloud／本地备份恢复。
    public func save(_ typography: ReaderTypography) throws {
        // 落盘前归一化：只允许合法档位进入持久化（越界值 snap）。
        let data = try JSONEncoder().encode(TypographyTiers.normalize(typography))
        let result = Persist.write(data, to: fileURL, payload: .typographyPreference,
                                   excludedFromBackup: false)
        try result.get()
    }
}
