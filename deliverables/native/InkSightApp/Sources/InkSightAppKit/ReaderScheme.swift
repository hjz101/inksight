import Foundation
import InkSightCore

// MARK: - ReaderScheme（FR-028 阅读方案：玻璃参数＋字体＋动效）

/// 阅读方案（FR-028：「玻璃参数＋字体＋动效存为方案并分享」）。
///
/// 三部分：
/// - **玻璃参数**：主题皮肤（四层规格由 `ThemeSkinSpec.Skin` 决定）；
/// - **字体/排版**：`ReaderTypography`（阶段制，FR-009）；
/// - **动效**：`MotionSettings`（FR-030）。
///
/// **不含任何正文**（FR-025 同源纪律：导出只含用户偏好，绝不含书籍内容或凭据）。
public struct ReaderScheme: Codable, Equatable, Sendable {

    /// 方案格式版本（将来结构变更时用于迁移判断）。
    public static let currentVersion = 1

    public let version: Int
    /// 用户可见的名称（可空 → 展示为「未命名方案」）。
    public var name: String
    /// 玻璃/主题皮肤。
    public var skin: ThemeSkinSpec.Skin
    /// 排版（字体/字号档/行高/边距/缩进）。
    public var typography: ReaderTypography
    /// 动效开关。
    public var motion: MotionSettings
    /// 创建时间。
    public let createdAt: Date

    public init(name: String = "",
                skin: ThemeSkinSpec.Skin,
                typography: ReaderTypography,
                motion: MotionSettings,
                createdAt: Date = Date()) {
        self.version = ReaderScheme.currentVersion
        self.name = name
        self.skin = skin
        self.typography = typography
        self.motion = motion
        self.createdAt = createdAt
    }

    /// 展示名（空名回落「未命名方案」，**不预设任何值**）。
    public var displayName: String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "未命名方案" : n
    }

    public static let defaultDisplayName = "未命名方案"
}

// MARK: - ReaderSchemeCodec（编码/解码，可分享的字符串形态）

/// 方案编解码（FR-028 分享）。
///
/// 用 JSON（而非二进制）：**可读、可粘贴、可人工检查**——
/// 分享形态一旦不可读，"用户拷给朋友的到底是什么"就没人能验证。
public enum ReaderSchemeCodec {

    /// 编码为可分享字符串。
    public static func encode(_ scheme: ReaderScheme) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(scheme)
        return String(decoding: data, as: UTF8.self)
    }

    /// 从字符串解码（导入）。
    ///
    /// - Throws: 格式错误/版本不支持时抛错——**不静默回落到默认方案**
    ///   （静默回落会让用户以为"导入成功"，实际什么也没变）。
    public static func decode(_ string: String) throws -> ReaderScheme {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = string.data(using: .utf8) else {
            throw ReaderSchemeError.invalidEncoding
        }
        let scheme: ReaderScheme
        do {
            scheme = try decoder.decode(ReaderScheme.self, from: data)
        } catch {
            throw ReaderSchemeError.malformed(error.localizedDescription)
        }
        guard scheme.version == ReaderScheme.currentVersion else {
            throw ReaderSchemeError.unsupportedVersion(scheme.version)
        }
        return scheme
    }
}

/// 方案编解码错误（**每种失败都有明确原因**，便于向用户解释）。
public enum ReaderSchemeError: LocalizedError, Equatable {
    case invalidEncoding
    case malformed(String)
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "方案文本编码无法识别"
        case .malformed(let detail):
            return "方案格式不正确：\(detail)"
        case .unsupportedVersion(let v):
            return "方案版本 \(v) 不受支持（当前支持 \(ReaderScheme.currentVersion)）"
        }
    }
}

// MARK: - ReaderSchemeStore（本地方案集）

/// 本地方案仓库（保存/列出/删除；经 `Persist` 单门落盘，可备份）。
public final class ReaderSchemeStore: @unchecked Sendable {

    private var schemes: [ReaderScheme] = []
    private let lock = NSLock()

    public static let defaultDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("com.inksight/schemes", isDirectory: true)
    }()

    public static let defaultFileName = "ReaderSchemes.json"

    public let fileURL: URL

    public init(fileURL: URL = defaultDirectory.appendingPathComponent(defaultFileName)) {
        self.fileURL = fileURL
        try? load()
    }

    /// 保存方案（同名覆盖 —— 名称是用户可见标识）。
    public func save(_ scheme: ReaderScheme) throws {
        lock.lock()
        if let idx = schemes.firstIndex(where: { $0.displayName == scheme.displayName }) {
            schemes[idx] = scheme
        } else {
            schemes.append(scheme)
        }
        let snapshot = schemes
        lock.unlock()
        try persist(snapshot)
    }

    public func all() -> [ReaderScheme] {
        lock.lock(); defer { lock.unlock() }
        return schemes.sorted { $0.createdAt > $1.createdAt }
    }

    public func remove(named name: String) throws {
        lock.lock()
        schemes.removeAll { $0.displayName == name }
        let snapshot = schemes
        lock.unlock()
        try persist(snapshot)
    }

    private func persist(_ snapshot: [ReaderScheme]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try Persist.write(data, to: fileURL, payload: .typographyPreference,
                          excludedFromBackup: false).get()
    }

    private func load() throws {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([ReaderScheme].self, from: data) else { return }
        lock.lock(); defer { lock.unlock() }
        schemes = decoded
    }
}
