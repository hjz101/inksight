import Foundation
import InkSightCore

// MARK: - 主题模型（FR-010 夜间与主题，依 DESIGN §1.1 / §3）

/// 主题皮肤（DESIGN §3）：默认「雪纸」（浅色纸面）。
///
/// 判据（DESIGN §3）：换主题时四项同时变——图标、强调色、玻璃 tint、转场配色。
public enum ThemeSkin: String, Codable, CaseIterable, Sendable {
    /// 默认主题「雪纸」：浅色纸面
    case snowPaper
    /// 「夜航」：深色底（`#121212`）
    case nightVoyage

    /// 纸面底色（正文区背景）。
    public var paperBackgroundHex: String {
        switch self {
        case .snowPaper:   return "#FCFCFB"   // 近白纸面（当前实现 Color(white: 0.98) 同源）
        case .nightVoyage: return "#121212"
        }
    }
}

/// 夜航正文对比档（DESIGN §1.1：**两档**，不设第三档）。
///
/// **高对比是夜航的色值档位，不是独立主题**——不参与主题 × 字号组合。
public enum NightContrast: String, Codable, CaseIterable, Sendable {
    /// 默认 #8A8A8A on #121212 = 5.4:1（20pt 属 WCAG 大字，满足 AA + AAA 大字 4.5:1）
    case standard
    /// 选配高对比 #CFCDC7 ≈ 13:1
    case highContrast

    public var textHex: String {
        switch self {
        case .standard:     return "#8A8A8A"
        case .highContrast: return "#CFCDC7"
        }
    }

    /// 对比度（DESIGN 给定值）。
    public var contrastRatio: Double {
        switch self {
        case .standard:     return 5.4
        case .highContrast: return 13.0
        }
    }
}

// MARK: - ThemeState（完整主题状态）

/// 主题状态：皮肤 ＋ 夜航对比档 ＋ 切换模式（可持久化）。
public struct ThemeState: Codable, Equatable, Sendable {
    public var skin: ThemeSkin
    /// 仅在 `.nightVoyage` 生效（雪纸主题用深色字，此字段被忽略）。
    public var nightContrast: NightContrast
    public var mode: ThemeMode

    public init(skin: ThemeSkin = .snowPaper,
                nightContrast: NightContrast = .standard,
                mode: ThemeMode = .byTime) {
        self.skin = skin
        self.nightContrast = nightContrast
        self.mode = mode
    }

    /// 正文前景色（十六进制）。
    ///
    /// - 雪纸：深色字（`#1A1A1C`，与当前实现墨色 `CGColor(0.10,0.10,0.12)` 同源）；
    /// - 夜航：按 `nightContrast` 两档取值。
    public var textHex: String {
        switch skin {
        case .snowPaper:   return "#1A1A1C"
        case .nightVoyage: return nightContrast.textHex
        }
    }

    /// 纸面背景色（十六进制）。
    public var backgroundHex: String { skin.paperBackgroundHex }

    /// 解析当前应生效的主题（按时段自动切夜航）。
    ///
    /// - `.manual` → 用当前 `skin`；
    /// - `.byTime` → 夜间时段（22:00–6:00）切 `nightVoyage`，白天 `snowPaper`；
    /// - `.byAmbientLight` → 本机无环境光传感器，**退化为按时段**（诚实降级，不伪装）。
    ///
    /// - Parameter hour: 当前小时（0–23），由调用方传入以便测试。
    public func effectiveSkin(hour: Int) -> ThemeSkin {
        switch mode {
        case .manual:
            return skin
        case .byTime, .byAmbientLight:
            return ThemeState.isNightHour(hour) ? .nightVoyage : .snowPaper
        }
    }

    /// 是否夜间时段（22:00–6:00，含 22 不含 6）。
    public static func isNightHour(_ hour: Int) -> Bool {
        hour >= 22 || hour < 6
    }
}

// MARK: - ThemeMode（切换来源）

/// 主题切换模式：按时段 / 按环境光 / 手动（FR-010 原文三项）。
public enum ThemeMode: String, Codable, CaseIterable, Sendable {
    case byTime
    case byAmbientLight
    case manual
}

// MARK: - ThemeStore（持久化）

/// 主题状态仓库：经 `Persist` 落盘（用户偏好，可备份）。
public final class ThemeStore: @unchecked Sendable {

    public static let defaultDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("com.inksight/theme", isDirectory: true)
    }()

    public static let defaultFileName = "Theme.json"

    public let fileURL: URL

    public init(fileURL: URL = defaultDirectory.appendingPathComponent(defaultFileName)) {
        self.fileURL = fileURL
    }

    /// 读取主题状态；无文件/解码失败 → 默认（按时段）。**不抛错、不伪造**。
    public func load() -> ThemeState {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(ThemeState.self, from: data) else {
            return ThemeState()
        }
        return decoded
    }

    public func save(_ state: ThemeState) throws {
        let data = try JSONEncoder().encode(state)
        // 用户偏好 → 可备份
        try Persist.write(data, to: fileURL, payload: .typographyPreference,
                          excludedFromBackup: false).get()
    }
}
