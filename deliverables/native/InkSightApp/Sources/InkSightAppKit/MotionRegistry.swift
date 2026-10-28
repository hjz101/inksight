import Foundation
import SwiftUI

// MARK: - MotionRegistry（FR-030，构建期强制）

/// 13 个动效 ID（**穷举，冻结**）。CaseIterable ＋ Registry 内 exhaustive switch：
/// **新增一个 case 而未在 Registry 登记 → 编译失败**（Switch must be exhaustive）。
/// 枚举 raw value ＝ 英文名（DESIGN §4.1 定版），中文名在 spec 里。
/// 命名依据：名字描述行为，不描述来源或意象（改名检查清单第 4 条）。
public enum MotionID: String, CaseIterable, Sendable {
    case t1BookOpen        // T1 书架翻开
    case t2VersionSwap     // T2 版本层翻片
    case t3ThemeWipe       // T3 色带漫延
    case t4RestoreSettle   // T4 位置记忆回弹
    case t5SwitchRipple    // T5 切换涟漪
    case t6InkGrow         // T6 墨量错峰生长
    case egg1CoverLiquid   // EGG1 封面液体流动 / 书脊抽出（同 ID 双表现，variant 区分）
    case egg2PinchSpine    // EGG2 捏合书脊视图
    case egg3PaperPull     // EGG3 纸质下拉回弹
    case egg4DogEar        // EGG4 页角折角
    case egg5ShakePanel    // EGG5 摇一摇唤面板
    case uit1ChromeToggle  // UIT1 工具条显隐（chromeToggle 语义名，D-39/D-46）
    case uit2EdgeBack      // UIT2 边缘单指侧滑退出（仅滚动/直切模式注册，D-52）
}

/// EGG1 同 ID 双表现的 variant（单 case ＋ 参数，**不分裂枚举**——
/// 枚举一分裂，"未登记即构建失败"的检查就失去意义：同一语义多个 case，登记者随手选一个就能绕过）。
public enum Egg1Variant: String, Sendable, CaseIterable {
    case liquid   // 封面液体流动
    case lift     // 书脊抽出
}

/// 关闭态下触发逻辑的处置（DESIGN §8 关态触发规则的三分类）。
/// 判据：**关动效只能减掉动画，不能减掉能力**；彩蛋可注销的前提是
/// 存在非手势等价路径——缺一则必须是 `.keepTrigger`。
public enum TriggerPolicy: Equatable, Sendable {
    /// 触发逻辑保留，全局关时不播动画（功能性动效／装饰性反馈）。
    case keepTrigger
    /// 触发逻辑一并注销（纯彩蛋）。关联值＝非手势等价路径（nil＝纯装饰，无功能损失）。
    case dropTrigger(equivalentPath: String?)
}

/// 单条动效登记项。
public struct MotionSpec: Equatable, Sendable {
    public let id: MotionID
    public let englishName: String
    public let chineseName: String
    /// A 档：全部可关（关闭态＝不播动画路径，非时长置 0）。
    public let closable: Bool
    public let triggerPolicy: TriggerPolicy
    /// 关闭态的可断言描述（"不可断言的描述等于没有描述"）。
    public let offStateAssertion: String

    public init(id: MotionID, englishName: String, chineseName: String,
                triggerPolicy: TriggerPolicy, offStateAssertion: String) {
        self.id = id
        self.englishName = englishName
        self.chineseName = chineseName
        self.closable = true
        self.triggerPolicy = triggerPolicy
        self.offStateAssertion = offStateAssertion
    }
}

// MARK: - Registry（穷举 switch＝构建期强制）

public enum MotionRegistry {

    /// 全部登记项。**此 switch 必须穷举 MotionID**——新增 case 而不在此登记，
    /// 编译直接失败（FR-030：未登记构建失败）。
    public static let all: [MotionSpec] = {
        var specs: [MotionSpec] = []
        for id in MotionID.allCases {
            switch id {   // 穷举：新增 case 不加分支即编译失败
            case .t1BookOpen:
                specs.append(MotionSpec(id: id, englishName: "bookOpen", chineseName: "书架翻开",
                    triggerPolicy: .keepTrigger, offStateAssertion: "点击即开，无 3D 无缩放，z0/z1 不创建"))
            case .t2VersionSwap:
                specs.append(MotionSpec(id: id, englishName: "versionSwap", chineseName: "版本层翻片",
                    triggerPolicy: .keepTrigger, offStateAssertion: "版本层瞬时替换，rect 不动"))
            case .t3ThemeWipe:
                specs.append(MotionSpec(id: id, englishName: "themeWipe", chineseName: "色带漫延",
                    triggerPolicy: .keepTrigger, offStateAssertion: "主题直切，无遮挡层"))
            case .t4RestoreSettle:
                specs.append(MotionSpec(id: id, englishName: "restoreSettle", chineseName: "位置记忆回弹",
                    triggerPolicy: .keepTrigger, offStateAssertion: "直切回位＋位置标签（反馈必须留，动画不必播）"))
            case .t5SwitchRipple:
                specs.append(MotionSpec(id: id, englishName: "switchRipple", chineseName: "切换涟漪",
                    triggerPolicy: .keepTrigger, offStateAssertion: "0ms 静态成功态（反馈必须留，动画不必播）"))
            case .t6InkGrow:
                specs.append(MotionSpec(id: id, englishName: "inkGrow", chineseName: "墨量错峰生长",
                    triggerPolicy: .keepTrigger, offStateAssertion: "全部直接置终态，同帧出现"))
            case .egg1CoverLiquid:
                specs.append(MotionSpec(id: id, englishName: "coverLiquid", chineseName: "封面液体流动 / 书脊抽出",
                    triggerPolicy: .dropTrigger(equivalentPath: nil),   // 纯装饰，无功能损失
                    offStateAssertion: "长按逻辑不注册，装饰层不创建"))
            case .egg2PinchSpine:
                specs.append(MotionSpec(id: id, englishName: "pinchSpine", chineseName: "捏合书脊视图",
                    triggerPolicy: .dropTrigger(equivalentPath: "书架视图切换条按钮"),
                    offStateAssertion: "捏合逻辑保留，无过渡直切视图"))
            case .egg3PaperPull:
                specs.append(MotionSpec(id: id, englishName: "paperPull", chineseName: "纸质下拉回弹",
                    triggerPolicy: .keepTrigger,   // 装饰层不创建，下拉刷新仍生效（功能不能关）
                    offStateAssertion: "装饰层不创建，下拉刷新生效"))
            case .egg4DogEar:
                specs.append(MotionSpec(id: id, englishName: "dogEar", chineseName: "页角折角",
                    triggerPolicy: .dropTrigger(equivalentPath: "chrome 菜单加书签"),
                    offStateAssertion: "折角手势不注册，加书签走菜单（功能不丢）"))
            case .egg5ShakePanel:
                specs.append(MotionSpec(id: id, englishName: "shakePanel", chineseName: "摇一摇唤面板",
                    triggerPolicy: .dropTrigger(equivalentPath: "chrome 菜单换一份文件"),
                    offStateAssertion: "摇动无响应（限流一并停跑），面板不出现"))
            case .uit1ChromeToggle:
                specs.append(MotionSpec(id: id, englishName: "chromeToggle", chineseName: "工具条显隐",
                    triggerPolicy: .keepTrigger, offStateAssertion: "直接显隐（仿真/双页下顶栏返回恒可达）"))
            case .uit2EdgeBack:
                specs.append(MotionSpec(id: id, englishName: "edgeBack", chineseName: "边缘单指侧滑退出",
                    triggerPolicy: .keepTrigger, offStateAssertion: "直切退出，手势仍可用（仅滚动/直切模式注册）"))
            }
        }
        return specs
    }()

    public static func spec(for id: MotionID) -> MotionSpec {
        // 穷举查找：Registry 与 MotionID 永不脱钩
        for spec in all where spec.id == id { return spec }
        fatalError("MotionRegistry 未登记 \(id)——FR-030 不允许（此行不可达：all 由穷举 switch 生成）")
    }

    /// EGG1 variant（同 ID 双表现）。
    public static func egg1Variants(for id: MotionID) -> [Egg1Variant] {
        id == .egg1CoverLiquid ? Egg1Variant.allCases : []
    }
}

// MARK: - 动效分组与「有独立开关」集合（开发包 #7 · FR-030 ②）

/// 设置页的动效分组（FR-030 原文②「按『转场 4／彩蛋 5／手势 2』三组」）。
/// 中文名在此**单一来源**——UI 不另写一份名字（同 `MotionSpec.chineseName` 的纪律）。
public enum MotionGroup: String, CaseIterable, Sendable {
    case transition   // 转场
    case easterEgg    // 彩蛋
    case gesture      // 手势

    public var chineseName: String {
        switch self {
        case .transition: return "转场"
        case .easterEgg:  return "彩蛋"
        case .gesture:    return "手势"
        }
    }
}

public extension MotionRegistry {

    /// **有独立开关的动效集合：恰好 11 个**（FR-030 原文②「可关 11 个」）。
    ///
    /// 严格集合：`T1／T2／T3／T6／EGG1／EGG2／EGG3／EGG4／EGG5／UIT1／UIT2`。
    /// **T4／T5 不在其中**——FR-030 明文「T4 无单独开关（直切回位＋位置标签）、
    /// T5 无单独开关（降级 0ms 静态态）」，故 UI 上不得出现这两行开关。
    ///
    /// 用**穷举 switch** 派生：新增一个 `MotionID` case 而未在此登记 → **编译失败**
    /// （同 FR-030「未登记构建失败」的纪律，避免集合与枚举静默脱钩）。
    ///
    /// 注意与 `MotionSpec.closable` 区分：`closable` ＝ A 档「全部可关」（13 个全为 true，
    /// 指「关掉时走不播动画路径」这一档位）；本集合 ＝ 「**是否给用户一个独立开关行**」。
    /// 两者不是一回事，故单列。
    static var perIDSwitchableIDs: [MotionID] {
        var ids: [MotionID] = []
        for id in MotionID.allCases {
            switch id {   // 穷举：新增 case 不加分支即编译失败
            case .t1BookOpen, .t2VersionSwap, .t3ThemeWipe, .t6InkGrow,
                 .egg1CoverLiquid, .egg2PinchSpine, .egg3PaperPull, .egg4DogEar, .egg5ShakePanel,
                 .uit1ChromeToggle, .uit2EdgeBack:
                ids.append(id)
            case .t4RestoreSettle, .t5SwitchRipple:
                continue   // FR-030 明文：T4／T5 无单独开关
            }
        }
        return ids
    }

    /// 某 ID 的分组归属（穷举 switch → 新增 case 编译失败）。
    ///
    /// T4／T5 归入「转场」组（语义归属），但**不进入 `ids(inGroup:)` 的结果**——
    /// 它们无独立开关，UI 上不生成这两行。
    static func group(for id: MotionID) -> MotionGroup {
        switch id {
        case .t1BookOpen, .t2VersionSwap, .t3ThemeWipe, .t4RestoreSettle, .t5SwitchRipple, .t6InkGrow:
            return .transition
        case .egg1CoverLiquid, .egg2PinchSpine, .egg3PaperPull, .egg4DogEar, .egg5ShakePanel:
            return .easterEgg
        case .uit1ChromeToggle, .uit2EdgeBack:
            return .gesture
        }
    }

    /// 某组内**有独立开关**的 ID（已剔除 T4／T5）。
    /// 预期规模：转场 4／彩蛋 5／手势 2。
    static func ids(inGroup group: MotionGroup) -> [MotionID] {
        perIDSwitchableIDs.filter { self.group(for: $0) == group }
    }
}

// MARK: - MotionCoordinator（唯一动画入口）

/// **唯一动画入口**：任何动画调用必须持 MotionID 经由本协调器。
///
/// 全局总关 ＝ **不播动画路径**（`withTransaction(Transaction(animation: nil))`），
/// **不是时长设 0**——`matchedGeometryEffect` 在时长 0 下仍会画一帧旧 frame。
/// 验收：首帧与末帧逐帧 diff 为 0 且无中间帧（截帧验证）。
///
/// **开发包 #7 扩展**：除全局总关外，支持 **per-ID 独立开关**（FR-030 原文②「可关 11 个」）。
/// 判定式为 `isEnabled(_:)` ＝ **全局总关 AND 未被单独关闭**——总关优先级最高，单 ID 开关不能绕过它。
@MainActor
public final class MotionCoordinator {

    /// 全局总关开关（FR-030）。
    public static let shared = MotionCoordinator()

    public private(set) var isMotionEnabled: Bool

    /// **系统「减弱动态效果」**（iOS 辅助功能开关）：**优先级最高**——开启时任何动效都不播。
    ///
    /// 与用户「总关」的**关键区别**（不得混为一谈）：
    /// - 用户总关 → `dropTrigger` 的彩蛋**连触发一起短路**（用户主动不要这个功能）；
    /// - 系统减弱动态效果 → **只去动画，不去功能**（摇一摇仍可唤面板，只是不播动画）。
    ///
    /// 由 UI 层在进入/离开场景时同步本值（观察 `@Environment(\.accessibilityReduceMotion)`）。
    public var systemReduceMotion: Bool = false

    /// **每 ID 独立开关（开发包 #7）**：只存「被单独关闭」的 ID。
    ///
    /// 为什么用 `Set<MotionID>` 而不是字典：① 判存 O(1)；② 与 `MotionSettings.perID`
    /// 的「true＝开」语义**正好互补**（存的是「关」的集合），转换只在
    /// `apply(_:)` 与 `currentSettings()` 两处发生，不散落。
    ///
    /// 为什么必须存在本类体内而不能用扩展：Swift 不允许在扩展里加存储属性。
    private var individuallyDisabled: Set<MotionID> = []

    public init(isMotionEnabled: Bool = true) {
        self.isMotionEnabled = isMotionEnabled
    }

    public func setMotionEnabled(_ enabled: Bool) {
        isMotionEnabled = enabled
    }

    // MARK: - per-ID 独立开关（FR-030 原文②）

    /// 该 ID 是否允许播动画 ＝ **全局总关 AND 未被单独关闭**。
    ///
    /// **全局总关优先级最高**：任何单 ID 开关都不能绕过总关——总关时即使某 ID 单独开着也不播。
    /// 本判定管的是「**功能与动画的联合**」（决定 `dropTrigger` 是否短路触发）。
    public func isEnabled(_ id: MotionID) -> Bool {
        isMotionEnabled && !individuallyDisabled.contains(id)
    }

    /// 是否**应播动画** ＝ `isEnabled(_:)` **AND** 系统未开启「减弱动态效果」。
    ///
    /// 与 `isEnabled(_:)` 的差别：系统减弱动态效果时**只去动画、不去功能**——
    /// 触发照常执行（状态变更生效），只是不播动画路径。
    public func shouldAnimate(_ id: MotionID) -> Bool {
        isEnabled(id) && !systemReduceMotion
    }

    /// 该 ID 是否被**单独**关闭（**不含**全局总关的影响）——UI 开关行状态取自此处。
    public func isIndividuallyDisabled(_ id: MotionID) -> Bool {
        individuallyDisabled.contains(id)
    }

    /// 设置某 ID 的独立开关（**只影响该 ID**，其余 ID 一律不受影响）。
    public func setEnabled(_ enabled: Bool, for id: MotionID) {
        if enabled {
            individuallyDisabled.remove(id)
        } else {
            individuallyDisabled.insert(id)
        }
    }

    /// 批量应用设置（来自持久化或 UI）——**不依赖磁盘**即可驱动任意开关组合。
    ///
    /// 语义：先写全局总关，再按 `perID` 写各 ID（缺键视为开）。
    public func apply(_ settings: MotionSettings) {
        isMotionEnabled = settings.globalEnabled
        individuallyDisabled = Set(
            MotionRegistry.perIDSwitchableIDs.filter { settings.perID[$0.rawValue] == false }
        )
    }

    /// 当前设置快照（供持久化）：形状恒为「全局 + 11 个可关 ID」。
    public func currentSettings() -> MotionSettings {
        var perID: [String: Bool] = [:]
        for id in MotionRegistry.perIDSwitchableIDs {
            perID[id.rawValue] = !individuallyDisabled.contains(id)
        }
        return MotionSettings(globalEnabled: isMotionEnabled, perID: perID)
    }

    /// 该播时返回该 ID 的标准动画；**总关、该 ID 被单独关闭、或系统开启「减弱动态效果」→ nil**（＝不播动画路径）。
    /// （真机曲线/时长由各动效实现自带，Registry 只裁决"播不播"。）
    public func animation(for id: MotionID) -> Animation? {
        shouldAnimate(id) ? .snappy(duration: MotionRegistry.spec(for: id).closable ? 0.3 : 0) : nil
    }

    /// 唯一播放入口。**总关或该 ID 被单独关闭**时按 `triggerPolicy` 分流：
    /// - keepTrigger：仍执行状态变更，但**无动画**（`withTransaction(animation: nil)`）——
    ///   「关动效只能减掉动画，不能减掉能力」；
    /// - dropTrigger：**连触发一起短路**（EGG5"摇动无响应、限流一并停跑"由此获得结构保证）。
    ///
    /// **系统「减弱动态效果」**（优先级最高）：**只去动画、不去功能**——触发照常执行、状态变更照常生效，
    /// 只是走不播动画路径。与用户总关的 dropTrigger 短路**语义不同**，不得混为一谈。
    ///
    /// 分流是**逐 ID** 的：单独关闭某 ID 时，其余 ID 照常播。
    public func perform(_ id: MotionID, _ changes: () -> Void) {
        let spec = MotionRegistry.spec(for: id)
        if !isEnabled(id) {
            if case .keepTrigger = spec.triggerPolicy {
                let transaction = Transaction(animation: nil)
                withTransaction(transaction) { changes() }
            }
            return   // dropTrigger：连触发一起短路
        }
        // 系统「减弱动态效果」优先级最高：只去动画，**不去功能**
        if systemReduceMotion {
            let transaction = Transaction(animation: nil)
            withTransaction(transaction) { changes() }
            return
        }
        withAnimation(.snappy(duration: 0.3)) { changes() }
    }
}
