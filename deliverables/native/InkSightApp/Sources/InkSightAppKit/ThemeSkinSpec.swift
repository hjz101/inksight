import Foundation
import SwiftUI
import InkSightCore

// MARK: - ThemeSkinSpec（FR-028 主题皮肤，DESIGN §3）

/// 主题皮肤规格（DESIGN §3.1：**三套做全四层**）。
///
/// **判据（原文）**：换主题时**四项同时变**才算通过——
/// ① 图标（色/描边/端点）② 强调色（按钮/选中/进度/开关）
/// ③ 玻璃 tint / 色散 ④ 转场配色。任一项不随主题动即判未完成。
///
/// **token 化（原文）**：`iconStroke` / `iconCap` / `radiusShift` 三个值**禁止硬编码**，
/// 「改主题必须同时改这三个值」。
public enum ThemeSkinSpec {

    /// 主题标识（三套：雪纸基准 / 夜航暗底极值 / 蜜桃汽水年轻向极值）。
    public enum Skin: String, Codable, CaseIterable, Sendable {
        case snowPaper       // 雪纸（基准）
        case nightVoyage     // 夜航（暗底极值）
        case peachSoda       // 蜜桃汽水（年轻向极值）

        public var displayName: String {
            switch self {
            case .snowPaper:   return "雪纸"
            case .nightVoyage: return "夜航"
            case .peachSoda:   return "蜜桃汽水"
            }
        }
    }

    /// 图标端点形状（① 图标：端点）。
    public enum IconCap: String, Codable, Sendable {
        case butt    // 直角端
        case round   // 圆角端
    }

    /// 四层规格。
    public struct Spec: Equatable, Sendable {
        // ① 图标
        public let iconColorHex: String
        public let iconStroke: Double
        public let iconCap: IconCap
        // ② 强调色
        public let accentHex: String
        // ③ 玻璃
        public let glassTintHex: String
        public let glassTintOpacity: Double
        public let glassDispersion: Double
        // ④ 转场配色（起 → 止）
        public let transitionFromHex: String
        public let transitionToHex: String
        // token：圆角偏移（蜜桃汽水 +4）
        public let radiusShift: Double

        public init(iconColorHex: String, iconStroke: Double, iconCap: IconCap,
                    accentHex: String,
                    glassTintHex: String, glassTintOpacity: Double, glassDispersion: Double,
                    transitionFromHex: String, transitionToHex: String,
                    radiusShift: Double) {
            self.iconColorHex = iconColorHex
            self.iconStroke = iconStroke
            self.iconCap = iconCap
            self.accentHex = accentHex
            self.glassTintHex = glassTintHex
            self.glassTintOpacity = glassTintOpacity
            self.glassDispersion = glassDispersion
            self.transitionFromHex = transitionFromHex
            self.transitionToHex = transitionToHex
            self.radiusShift = radiusShift
        }
    }

    /// 取某主题的四层规格（DESIGN §3.1 表格逐值）。
    public static func spec(for skin: Skin) -> Spec {
        switch skin {
        case .snowPaper:
            return Spec(iconColorHex: "#B8452F", iconStroke: 2, iconCap: .butt,
                        accentHex: "#B8452F",
                        glassTintHex: "#FFFFFF", glassTintOpacity: 0.28, glassDispersion: 0.35,
                        transitionFromHex: "#B8452F", transitionToHex: "#E8A38F",
                        radiusShift: 0)
        case .nightVoyage:
            return Spec(iconColorHex: "#6E8BFF", iconStroke: 2, iconCap: .round,
                        accentHex: "#6E8BFF",
                        glassTintHex: "#1C1C1E", glassTintOpacity: 0.45, glassDispersion: 0.20,
                        transitionFromHex: "#6E8BFF", transitionToHex: "#3A4A80",
                        radiusShift: 0)
        case .peachSoda:
            // 蜜桃汽水：描边 **2.5pt** ＋ **全站圆角 +4**
            return Spec(iconColorHex: "#FF6B5A", iconStroke: 2.5, iconCap: .round,
                        accentHex: "#FF6B5A",
                        glassTintHex: "#FFD9C9", glassTintOpacity: 0.30, glassDispersion: 0.45,
                        transitionFromHex: "#FF6B5A", transitionToHex: "#FFB3A3",
                        radiusShift: 4)
        }
    }

    /// 由 `ReadingTheme.ThemeSkin` 映射到皮肤规格（兼容既有主题两档）。
    ///
    /// 既有 `ThemeSkin.snowPaper/nightVoyage` 与本节 `Skin` 一一对应；
    /// 蜜桃汽水为新增第三套（既有代码未引用，属向后兼容扩展）。
    public static func spec(forLegacy skin: ThemeSkin) -> Spec {
        switch skin {
        case .snowPaper:   return spec(for: .snowPaper)
        case .nightVoyage: return spec(for: .nightVoyage)
        }
    }
}

// MARK: - ThemeSkinStore（FR-028 皮肤持久化）

/// 皮肤选择持久化（FR-028：玻璃参数＋字体＋动效存为方案并分享——本包落地**皮肤部分**）。
public final class ThemeSkinStore: @unchecked Sendable {

    private let lock = NSLock()
    private var current: ThemeSkinSpec.Skin = .snowPaper

    public static let defaultDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("com.inksight/skin", isDirectory: true)
    }()

    public static let defaultFileName = "ThemeSkin.json"

    public let fileURL: URL

    public init(fileURL: URL = defaultDirectory.appendingPathComponent(defaultFileName)) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(ThemeSkinSpec.Skin.self, from: data) {
            current = decoded
        }
    }

    public var skin: ThemeSkinSpec.Skin {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    public var spec: ThemeSkinSpec.Spec { ThemeSkinSpec.spec(for: skin) }

    public func setSkin(_ skin: ThemeSkinSpec.Skin) throws {
        lock.lock()
        current = skin
        lock.unlock()
        let data = try JSONEncoder().encode(skin)
        try Persist.write(data, to: fileURL, payload: .typographyPreference,
                          excludedFromBackup: false).get()
    }
}
