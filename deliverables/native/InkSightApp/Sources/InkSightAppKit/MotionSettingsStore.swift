import Foundation
import InkSightCore

// MARK: - MotionSettings（FR-030 ②：每 ID 独立开关的持久化模型）

/// 动效开关设置（FR-030 原文②「可关 11 个 …… 设置页按『转场 4／彩蛋 5／手势 2』三组、
/// 每 ID 一行独立开关并持久化」）。
///
/// 契约：
/// - `globalEnabled` ＝ **全局总关**（优先级最高，见 `MotionCoordinator.isEnabled(_:)`）；
/// - `perID` ＝ **每 ID 独立开关**，键为 `MotionID.rawValue`，值 `true`＝开／`false`＝关；
/// - `perID` **只收录 11 个有独立开关的 ID**（T1／T2／T3／T6／EGG1–EGG5／UIT1／UIT2）。
///   **T4／T5 无单独开关**（FR-030 明文：T4 直切回位＋位置标签、T5 降级 0ms 静态成功态），
///   故它们既不在 `perID` 里，UI 上也不出现这两行开关。
/// - **绝不含** `pageIndex`、正文、章节内容等任何正文类字段（定位铁律同源：
///   落盘模型只存派生开关状态，不存任何内容）。
public struct MotionSettings: Codable, Equatable, Sendable {

    /// 全局总关（FR-030）。
    public var globalEnabled: Bool

    /// 每 ID 独立开关：键＝`MotionID.rawValue`，值 `true`＝开／`false`＝关。
    public var perID: [String: Bool]

    public init(globalEnabled: Bool = true, perID: [String: Bool] = [:]) {
        self.globalEnabled = globalEnabled
        self.perID = perID
    }

    /// 默认态：**全部开启**（无文件时的诚实回退——不是「空设置」，是明确的「全开」）。
    public static var defaultAllEnabled: MotionSettings {
        MotionSettings(
            globalEnabled: true,
            perID: Dictionary(uniqueKeysWithValues: MotionRegistry.perIDSwitchableIDs.map { ($0.rawValue, true) })
        )
    }

    /// 某 ID 的开关状态。**缺键视为开启**——默认全开，缺键不得误关（fail-open 于「动效」，
    /// 但总关由 `globalEnabled` 单独承载，不受此影响）。
    public func isEnabled(_ id: MotionID) -> Bool {
        perID[id.rawValue] ?? true
    }

    /// 归一：补齐 11 个可关 ID 的缺省（缺＝开），**剔除不在可关集合内的键**。
    /// 用于「读到的旧文件可能缺键/多键」的收敛，保证落盘形状稳定、可 diff。
    public func normalized() -> MotionSettings {
        var perID: [String: Bool] = [:]
        for id in MotionRegistry.perIDSwitchableIDs {
            perID[id.rawValue] = self.perID[id.rawValue] ?? true
        }
        return MotionSettings(globalEnabled: globalEnabled, perID: perID)
    }
}

// MARK: - MotionSettingsStore（单门 JSON 原子写）

/// 动效开关持久化：单门 JSON 落盘，原子写 `[.atomic]`（与开发包 #6 `TypographyPresetStore` 同源模式）。
///
/// 备份策略：**不设 `NSURLIsExcludedFromBackupKey`**——动效开关属**用户偏好**，应随备份恢复
/// （与 #3 `SQLiteCache` 的排除备份相反：SQLiteCache 存的是可重建的分页结构元数据，
/// 而动效开关是用户设置，丢备份即丢设置）。
///
/// 落盘内容只有开关布尔值：**无正文、无 pageIndex、无任何内容类字段**。
public final class MotionSettingsStore: @unchecked Sendable {

    /// 默认目录：`Application Support/com.inksight/motion`（沿用 #6 建立的
    /// 「App Support/com.inksight/ 下按功能分目录」约定）。
    public static let defaultDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("com.inksight/motion", isDirectory: true)
    }()

    public static let defaultFileName = "MotionSettings.json"

    public let fileURL: URL

    /// - Parameter fileURL: 落盘路径；默认 `defaultDirectory/defaultFileName`。
    public init(fileURL: URL = defaultDirectory.appendingPathComponent(defaultFileName)) {
        self.fileURL = fileURL
    }

    /// 读取动效开关。
    ///
    /// 诚实回退：无文件 / 读取失败 / 解码失败 → 全部开启的默认态，
    /// **不抛错、不伪造**（「无文件」与「用户显式全关」是两件事，不得混淆）。
    public func load() -> MotionSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .defaultAllEnabled }
        guard let data = try? Data(contentsOf: fileURL) else { return .defaultAllEnabled }
        guard let decoded = try? JSONDecoder().decode(MotionSettings.self, from: data) else {
            return .defaultAllEnabled
        }
        return decoded.normalized()
    }

    /// 持久化动效开关：经 `Persist` 落盘单门（E-04）原子写。
    public func save(_ settings: MotionSettings) throws {
        let data = try JSONEncoder().encode(settings.normalized())
        let result = Persist.write(data, to: fileURL, payload: .motionPreference,
                                   excludedFromBackup: false)
        try result.get()
    }
}
