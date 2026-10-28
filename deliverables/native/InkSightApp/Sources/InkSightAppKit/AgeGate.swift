import Foundation
import SwiftUI
import InkSightCore

// MARK: - GlassSpec（材质三档，数据层——InkSightAppKit 可测）

/// 玻璃强度三档（DESIGN §2 定版）：**L1/L2/L3 只定义 tint 强度，不存在材质参数切换**。
/// `.regular`/`.identity` 是 `Glass` 变体、`.interactive()` 是交互开关，都不是强度档。
/// **禁止在玻璃视图树内使用 `.thinMaterial`/`.regularMaterial`/`.thickMaterial`**
/// （Material 是旧材质系统，与 Liquid Glass 混用会同时损伤性能与观感一致性）。
///
/// spacing 20 为**设计默认值，待 POC-2 真机校准回填**（spacing 是融合阈值不是视觉间距；
/// 单元素容器无作用）。三档是否并为两档亦待 POC-2（同屏并排＋快速切换、亮暗两底分别判）。
public enum GlassStrength: String, CaseIterable, Sendable {
    case l1   // tint 0.14（TabBar 项 / 搜索胶囊 / 吸底操作条——可交互控件）
    case l2   // tint 0.20（继续阅读卡 / 分段控件 / 成就卡）
    case l3   // tint 0.28（换一份文件面板 / 阅读设置浮层 / 主题预览）

    public var tintOpacity: Double {
        switch self {
        case .l1: return 0.14
        case .l2: return 0.20
        case .l3: return 0.28
        }
    }
}

/// 玻璃材质常量（单一来源）。
public enum GlassSpec {
    /// `GlassEffectContainer` 融合阈值——**待 POC-2 真机校准回填，现为设计默认值**。
    public static let containerSpacing: CGFloat = 20
    /// D-38：底部 sheet 类容器统一口径——高度 ≤ 屏高 75%（639pt）＋ 内部滚动。
    public static let bottomSheetMaxHeight: CGFloat = 639
    /// 单块 30% 面积兜底（基准视口 393×852＝334,836pt²）**只适用于屏内卡片类**（D-38）。
    public static let singleCardAreaCap: CGFloat = 100_451
}

// MARK: - AgeGate（AGE_MATRIX v1.2 派生，逻辑层）

/// 三值语义（AGE_MATRIX §0）：**`∅` 不是"未填"，是该变体下不存在此能力，结构上不生成任何表述**。
public enum Presence: Equatable, Sendable {
    case granted     // ✓ 启用/生效
    case restricted  // ✗ 能力存在但在该态不生效（「…不可用」表述合法，通常不展示）
    case absent      // ∅ 该变体下不存在——必须沉默，不是生成后再隐藏
}

public enum AgeGateState: String, Codable, Sendable, CaseIterable {
    case adultConfirmed
    case minorConfirmed
    case ageUnresolved
    case unverified
}

public enum BuildVariant: String, Codable, Sendable, CaseIterable {
    case release   // 发行版（B 版，外发）
    case research  // 研究版（不外发）
}

/// 自动退出策略（AGE_MATRIX §1 末列）。
public enum AutoExitPolicy: Equatable, Sendable {
    case never                    // 仅监护验证退出（`.minorConfirmed`）
    case retryUntilResolved       // 持续重试至确定答案；成功当场解除并恢复阅读；不自动降级
    case onDidBecomeActive        // 仅从系统设置返回时检测一次
    case notApplicable            // 普通模式
}

/// 单元格：`(state, variant)` 派生的能力与策略。
public struct AgeGateCell: Equatable, Sendable {
    public let curfew: Bool
    /// 每日时长上限数值 **TBD（D-03，不写数字）**——矩阵只表达"该态套时长"。
    public let dailyQuota: Bool
    public let importFiles: Presence
    public let onlineSources: Presence
    public let settingsPath: Presence
    public let autoExit: AutoExitPolicy
}

/// 拦截页文案变体（curtain 键）。**按钮/条目数 2／1／0 ＝ curtain 文案键数**（AGE_MATRIX §1 拦截页键列）。
public struct CurtainCopy: Equatable, Sendable {
    /// 标题＝**banner 文本派生**（不变式 6：curtain 必须引用状态条同一文案键，不得另写字面）。
    public let title: String
    public let caption: String
}

// MARK: - 矩阵派生（视图层只读此处，禁止 if state == .xxx 拼文案）

public enum AgeGateMatrix {

    /// 逐 `(state, variant)` 的能力单元格（AGE_MATRIX §1 两表逐格对抄）。
    public static func cell(state: AgeGateState, variant: BuildVariant) -> AgeGateCell {
        switch (state, variant) {
        case (.adultConfirmed, .research):
            return AgeGateCell(curfew: false, dailyQuota: false,
                importFiles: .granted, onlineSources: .granted, settingsPath: .absent, autoExit: .notApplicable)
        case (.adultConfirmed, .release):
            return AgeGateCell(curfew: false, dailyQuota: false,
                importFiles: .granted, onlineSources: .absent, settingsPath: .absent, autoExit: .notApplicable)
        case (.minorConfirmed, _):
            // 宵禁 ✓、时长 ✓；release 下导入/在线/系统路径 ∅；research 在线 ✗、导入 ∅
            // 注：`importFiles` 两变体均为 ∅（AGE_MATRIX：minorConfirmed 导入 ∅），
            // 故不再用同值三目（旧写法 `variant == .release ? .absent : .absent` 是死代码）。
            let onlineSources: Presence = variant == .release ? .absent : .restricted
            return AgeGateCell(curfew: true, dailyQuota: true,
                importFiles: .absent, onlineSources: onlineSources, settingsPath: .absent, autoExit: .never)
        case (.ageUnresolved, _):
            // 宵禁 ✓、时长 ✗（D-38/合规侧定稿：可逆保护保留、不可逆豁免）；导入 ✓（离线首启不可用缺陷修复）
            let onlineSources: Presence = variant == .release ? .absent : .restricted
            return AgeGateCell(curfew: true, dailyQuota: false,
                importFiles: .granted, onlineSources: onlineSources, settingsPath: .granted,
                autoExit: .retryUntilResolved)
        case (.unverified, _):
            // 宵禁 ✗、时长 ✗（D-38：代价不可逆的保护豁免）；导入 ✓；在线 ✗/∅
            let onlineSources: Presence = variant == .release ? .absent : .restricted
            return AgeGateCell(curfew: false, dailyQuota: false,
                importFiles: .granted, onlineSources: onlineSources, settingsPath: .granted,
                autoExit: .onDidBecomeActive)
        }
    }

    /// 状态条主文案（文案键唯一来源，AGE_MATRIX §2）。`.adultConfirmed` 无状态条 → nil。
    public static func bannerText(state: AgeGateState, variant: BuildVariant) -> String? {
        switch (state, variant) {
        case (.adultConfirmed, _):          return nil   // 普通模式无状态条
        case (.minorConfirmed, _):          return "未成年人模式"
        case (.ageUnresolved, _):           return "年龄信息未完善 · 未成年人保护已生效"
        case (.unverified, .research):      return "年龄信息未完善：在线功能不可用"   // ✗ 语义合法
        case (.unverified, .release):       return "年龄信息未完善"                    // ∅ → 沉默（无在线能力可宣称受限）
        }
    }

    /// 拦截页文案变体：**2／1／0**（AGE_MATRIX §1 拦截页键列）。
    /// `.minorConfirmed` 无自动退出（不变式 3）；`.unverified` 无拦截页；release 在线 ∅ → 不出现"在线功能不可用"（不变式 2）。
    public static func curtainVariants(state: AgeGateState, variant: BuildVariant) -> [CurtainCopy] {
        let banner = bannerText(state: state, variant: variant)
        switch (state, variant) {
        case (.minorConfirmed, _):
            // 标题引用 banner 文本派生（不变式 6：curtain 不得另写字面）
            return [
                CurtainCopy(title: "\(banner ?? "") · 宵禁时段阅读暂停", caption: "每日 22:00–6:00 暂停阅读，时段结束后自动恢复"),
                CurtainCopy(title: "\(banner ?? "") · 今日阅读时长已用尽", caption: "次日自动恢复"),
            ]
        case (.ageUnresolved, _):
            return [CurtainCopy(title: "\(banner ?? "")，完善后即可继续阅读", caption: "")]
        default:
            return []
        }
    }

    /// 系统路径：**release ∅ → 结构上不生成**；research ✓ → 由 provider 提供，
    /// **取不到整句隐藏**（不硬编码、不自行翻译、不猜路径——写错的路径比不写更糟）。
    public static func settingsPathText(state: AgeGateState, variant: BuildVariant,
                                        provider: SettingsPathProviding) -> String? {
        guard cell(state: state, variant: variant).settingsPath == .granted else { return nil }
        return provider.settingsPath()   // nil → 整句隐藏
    }
}

/// 路径提供协议（可注入）。iOS 26 **未公开「App 年龄段」的深链与系统本地化菜单名**，
/// 默认实现为随包逐语言文案表（逐语言验收）；不支持的语言返回 nil → 整句隐藏。
/// 若 PM 坚持"取不到就隐藏"的严格口径，把默认实现换成返回 nil 即可（一行）。
public protocol SettingsPathProviding: Sendable {
    func settingsPath() -> String?
}

/// 随包逐语言文案表（非运行时猜译；逐语言验收由本地化流程负责）。
public struct BundledSettingsPathProvider: SettingsPathProviding {
    public init() {}
    public func settingsPath() -> String? {
        let locale = Locale.current.identifier
        if locale.hasPrefix("zh") { return "设置 › Apple 账户 › 个人信息 › App 年龄段" }
        if locale.hasPrefix("en") { return "Settings › Apple Account › Personal Information › App Age Range" }
        return nil   // 不支持的语言 → 整句隐藏（不猜译）
    }
}

// MARK: - 每日时长（D-03：TBD）

/// 每日阅读时长上限。**TBD（台账 D-03）——依据缺失，不是疏漏**：
/// 上限需参照法规与家长侧设置，本项目无依据则不造数；任何"补一个数"的提议
/// 须先给出依据并按台账流程回填。矩阵只表达"该态套时长"，不携带任何分钟数。
public enum DailyReadingQuota {
    /// 分钟数：TBD。调用方不得对此解包出数字用于倒计时（副文案不做倒计时）。
    public static var minutesTBD: Int? { nil }
}

// MARK: - Fetcher 访问策略映射（总册「三个门面」之一：未成年人模式整体 denyAll）

extension AgeGateState {
    /// 当前年龄态对应的出网访问策略（Fetcher 门面用）。
    ///
    /// - `.minorConfirmed` → **`.denyAll`**：未成年人模式整体断网（总册 Fetcher 门面；
    ///   技术约束清单 NFR-04「BGTaskScheduler 不注册抓取任务（同时是未成年人模式断网的实现基础）」）。
    /// - 其余三态 → `.allow`（网络能力是否"存在"由 `AgeGateMatrix.cell(...).onlineSources` 决定，
    ///   门面只管"策略允不允许出网"，两者正交：release 变体下 `onlineSources == .absent`
    ///   是"结构上不生成入口"，与"出网被策略拒绝"是两件事）。
    public var fetcherAccessPolicy: Fetcher.AccessPolicy {
        switch self {
        case .minorConfirmed: return .denyAll
        case .adultConfirmed, .ageUnresolved, .unverified: return .allow
        }
    }

    /// 应用当前年龄态到 Fetcher 全局策略（App 启动 / 年龄态变化时调用一次）。
    public func applyToFetcher() {
        Fetcher.currentPolicy = fetcherAccessPolicy
    }
}
