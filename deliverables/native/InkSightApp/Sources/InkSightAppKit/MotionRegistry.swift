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

// MARK: - MotionCoordinator（唯一动画入口）

/// **唯一动画入口**：任何动画调用必须持 MotionID 经由本协调器。
///
/// 全局总关 ＝ **不播动画路径**（`withTransaction(Transaction(animation: nil))`），
/// **不是时长设 0**——`matchedGeometryEffect` 在时长 0 下仍会画一帧旧 frame。
/// 验收：首帧与末帧逐帧 diff 为 0 且无中间帧（截帧验证）。
@MainActor
public final class MotionCoordinator {

    /// 全局总关开关（FR-030）。
    public static let shared = MotionCoordinator()

    public private(set) var isMotionEnabled: Bool

    public init(isMotionEnabled: Bool = true) {
        self.isMotionEnabled = isMotionEnabled
    }

    public func setMotionEnabled(_ enabled: Bool) {
        isMotionEnabled = enabled
    }

    /// 总关时返回 nil（= 不播动画路径）；开启时返回该 ID 的标准动画。
    /// （真机曲线/时长由各动效实现自带，Registry 只裁决"播不播"。）
    public func animation(for id: MotionID) -> Animation? {
        isMotionEnabled ? .snappy(duration: MotionRegistry.spec(for: id).closable ? 0.3 : 0) : nil
    }

    /// 唯一播放入口。总关时按 `triggerPolicy` 分流：
    /// - keepTrigger：仍执行状态变更，但**无动画**（`withTransaction(animation: nil)`）；
    /// - dropTrigger：**连触发一起短路**（EGG5"摇动无响应、限流一并停跑"由此获得结构保证）。
    /// 开启时按标准动画执行。
    public func perform(_ id: MotionID, _ changes: () -> Void) {
        let spec = MotionRegistry.spec(for: id)
        if !isMotionEnabled {
            if case .keepTrigger = spec.triggerPolicy {
                let transaction = Transaction(animation: nil)
                withTransaction(transaction) { changes() }
            }
            return   // dropTrigger：连触发一起短路
        }
        withAnimation(.snappy(duration: 0.3)) { changes() }
    }
}
