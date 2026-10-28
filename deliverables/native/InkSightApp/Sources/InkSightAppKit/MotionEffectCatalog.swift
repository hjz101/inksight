import Foundation
import SwiftUI

// MARK: - 动效实现目录（开发包 #9 · FR-030 从「登记完整」走到「真实可播可关」）

/// 动效的**开态视觉类型**（13 个动效各自的视觉实现）。
public enum MotionVisual: String, Equatable, Sendable {
    case scaleReveal     // T1 书架翻开
    case cardFlip        // T2 版本层翻片
    case colorBandWipe   // T3 色带漫延
    case settleSpring    // T4 位置记忆回弹
    case ripple          // T5 切换涟漪
    case staggeredGrow   // T6 墨量错峰生长
    case liquidCover     // EGG1 封面液体流动／书脊抽出
    case pinchSpine      // EGG2 捏合书脊视图
    case paperPull       // EGG3 纸质下拉回弹
    case dogEar          // EGG4 页角折角
    case shakePanel      // EGG5 摇一摇唤书摘
    case chromeSlide     // UIT1 工具条显隐
    case edgeSlide       // UIT2 边缘单指侧滑退出
}

/// 关态降级方式（与 `MotionSpec.offStateAssertion` 一一对应）。
public enum MotionOffState: String, Equatable, Sendable {
    /// 直切（无动画、无缩放、无 3D、无遮挡层）。
    case directSwap
    /// **反馈必须留，动画不必播**（T4 位置标签／T5 静态成功态）。
    case keepFeedback
    /// 装饰层**不创建**（EGG1 封面液体层／EGG3 纸质下拉装饰层／T3 色带遮挡层）。
    case noDecorationLayer
    /// 触发逻辑一并短路（EGG2／EGG4／EGG5：连触发一起停）。
    case shortCircuitTrigger
}

/// 关态下**必须保留**的反馈（T4／T5）。
///
/// FR-030 原文：「反馈必须留，动画不必播」——关态降级**不得**把反馈一起去掉。
public enum MotionRetainedFeedback: Equatable, Sendable {
    /// T4：位置记忆回弹关态 → 直切回位 ＋ **位置标签**。
    case positionLabel(String)
    /// T5：切换涟漪关态 → **0ms 静态成功态**。
    case staticSuccess(String)
}

/// 动效的**触发前置条件**。
public enum MotionActivation: Equatable, Sendable {
    /// 无额外条件（随时可触发）。
    case anytime
    /// 仅在阅读工具条**展开**时生效。
    ///
    /// EGG5 依据：摇一摇唤的是**书摘卡**；「换一个版本」的主路径恒在阅读工具条「换一个版本」按钮——
    /// 摇一摇**不**承担版本切换，故工具条未展开时摇动不唤书摘卡。
    case readingToolbarExpanded
}

/// 年龄态注册条件（DESIGN §4.1 原文口径）。
public enum MotionAgeGate: Equatable, Sendable {
    /// 无年龄限制。
    case any
    /// **仅 `.adultConfirmed` 注册**（EGG5）。
    case adultConfirmedOnly
}

/// 动效实现描述符（一个 MotionID 一条）。
public struct MotionEffectDescriptor: Equatable, Sendable {
    /// 动效 ID（与 `MotionID` 一一对应）。
    public let id: MotionID
    /// 开态视觉类型。
    public let visual: MotionVisual
    /// 关态降级方式。
    public let offState: MotionOffState
    /// **是否有独立开关**（T4／T5 无——FR-030 明文：直切回位＋位置标签／0ms 静态成功态）。
    public let hasIndependentSwitch: Bool
    /// 是否需要装饰层（关态必须**不创建**该层，而不是创建后隐藏）。
    public let requiresDecorationLayer: Bool
    /// 是否为手势类动效（关态时手势不注册，或注册但无过渡）。
    public let isGesture: Bool
    /// 触发前置条件。
    public let activation: MotionActivation
    /// 年龄态注册条件。
    public let ageGate: MotionAgeGate
    /// **动效期间是否插值材质参数**——**恒为 `false`**。
    ///
    /// FR-030 硬纪律：动效期间**禁止插值材质参数**（tint/blur/refraction）——
    /// 材质一变即触发 backdrop 全屏重算（四层叠加，成本远高于单层），T3 最易犯。
    /// 本字段把该纪律**写进类型**：测试逐条断言 13 条全为 `false`。
    public let interpolatesMaterial: Bool
    /// 该动效在哪些翻页模式下注册。
    ///
    /// UIT2：**仅滚动/直切模式注册**（`none`/`scroll`/`vertical`）；仿真（`flip`/`curl`）下**不注册**。
    public let registeredModes: Set<PageTurnMode>
    /// 关态下必须保留的反馈（T4／T5 非 nil，其余 nil）。
    public let retainedFeedback: MotionRetainedFeedback?
    /// 该动效在产品中的**自然触发位置**（DESIGN §4.1 原文口径，单一来源）——
    /// 供「把动效接到产品界面真实位置」时取用，避免各人各写一份。
    public let naturalTrigger: String

    public init(id: MotionID,
                visual: MotionVisual,
                offState: MotionOffState,
                hasIndependentSwitch: Bool,
                requiresDecorationLayer: Bool,
                isGesture: Bool,
                activation: MotionActivation = .anytime,
                ageGate: MotionAgeGate = .any,
                interpolatesMaterial: Bool = false,
                registeredModes: Set<PageTurnMode> = Set(PageTurnMode.allCases),
                retainedFeedback: MotionRetainedFeedback? = nil,
                naturalTrigger: String) {
        self.id = id
        self.visual = visual
        self.offState = offState
        self.hasIndependentSwitch = hasIndependentSwitch
        self.requiresDecorationLayer = requiresDecorationLayer
        self.isGesture = isGesture
        self.activation = activation
        self.ageGate = ageGate
        self.interpolatesMaterial = interpolatesMaterial
        self.registeredModes = registeredModes
        self.retainedFeedback = retainedFeedback
        self.naturalTrigger = naturalTrigger
    }
}

// MARK: - 动效曲线与时长（DESIGN §4.1 原文口径）

/// 动效曲线类型（DESIGN §4.1 原文口径的近似映射，单一来源）。
public enum MotionCurve: String, Equatable, Sendable {
    /// ease-out（快速起、慢收）。
    case easeOut
    /// spring（带阻尼的回弹）。
    case spring
    /// 指数衰减。
    case exponentialDecay
    /// 自定义 timing curve（DESIGN 的 `--e-open` / `--e-band` 等 token 的近似）。
    case custom
}

/// 动效的曲线与时长参数（DESIGN §4.1 原文口径）。
public struct MotionTiming: Equatable, Sendable {
    /// 时长（秒）。
    public let duration: Double
    /// 曲线类型。
    public let curve: MotionCurve
    /// spring 阻尼系数（仅 `.spring` 有意义）。
    public let damping: Double
    /// 错峰间隔（秒）——T6 25ms、EGG3 墨滴 60ms；其余为 0。
    public let stagger: Double

    public init(duration: Double, curve: MotionCurve, damping: Double = 0.8, stagger: Double = 0) {
        self.duration = duration
        self.curve = curve
        self.damping = damping
        self.stagger = stagger
    }

    /// 对应的 SwiftUI 动画（**只插值 opacity 与 transform**——不涉材质）。
    public var animation: Animation {
        switch curve {
        case .easeOut:
            return .easeOut(duration: duration)
        case .spring:
            return .spring(response: duration, dampingFraction: damping)
        case .exponentialDecay:
            return .timingCurve(0.2, 0.8, 0.2, 1, duration: duration)
        case .custom:
            return .timingCurve(0.2, 0.9, 0.2, 1, duration: duration)
        }
    }
}

// MARK: - MotionEffectCatalog（13 条，穷举派生）

/// 动效实现目录（开发包 #9）：**13 个 ID 一个不多一个不少**。
///
/// 派生方式：**穷举 switch** 覆盖全部 `MotionID`——新增一个 `MotionID` case 而未在此登记，
/// **编译直接失败**（同 FR-030「未登记构建失败」的纪律，避免目录与枚举静默脱钩）。
public enum MotionEffectCatalog {

    /// 全部 13 条实现描述。
    public static var all: [MotionEffectDescriptor] {
        MotionID.allCases.map { descriptor(for: $0) }
    }

    /// 某 ID 的实现描述（穷举 switch 派生）。
    public static func descriptor(for id: MotionID) -> MotionEffectDescriptor {
        switch id {   // 穷举：新增 MotionID case 不加分支即编译失败
        case .t1BookOpen:
            // 书架翻开：开态 z0/z1 两层＋翻起；关态「点击即开，无 3D 无缩放，z0/z1 不创建」
            return MotionEffectDescriptor(id: id, visual: .scaleReveal, offState: .directSwap,
                                          hasIndependentSwitch: true, requiresDecorationLayer: false,
                                          isGesture: false,
                                          naturalTrigger: "书架卡片（rect 左边缘＝书脊线）→ 全屏")
        case .t2VersionSwap:
            // 版本层翻片：开态 3D 翻片；关态「版本层瞬时替换，rect 不动」
            return MotionEffectDescriptor(id: id, visual: .cardFlip, offState: .directSwap,
                                          hasIndependentSwitch: true, requiresDecorationLayer: false,
                                          isGesture: false,
                                          naturalTrigger: "「换一个版本」面板：旧版本层左滑出淡出、新层滑入（书脊本身不动）")
        case .t3ThemeWipe:
            // 色带漫延：开态纯色色带扫过；关态「主题直切，无遮挡层」（色带层不创建）
            return MotionEffectDescriptor(id: id, visual: .colorBandWipe, offState: .noDecorationLayer,
                                          hasIndependentSwitch: true, requiresDecorationLayer: true,
                                          isGesture: false,
                                          naturalTrigger: "主题切换（色带层为纯色渐变，不是玻璃）")
        case .t4RestoreSettle:
            // 位置记忆回弹：**无独立开关**；总关降级为「直切回位＋位置标签」（反馈必须留）
            return MotionEffectDescriptor(id: id, visual: .settleSpring, offState: .keepFeedback,
                                          hasIndependentSwitch: false, requiresDecorationLayer: false,
                                          isGesture: false,
                                          retainedFeedback: .positionLabel("第 12 章 · 位置已恢复"),
                                          naturalTrigger: "恢复上次阅读位置（回弹落位）")
        case .t5SwitchRipple:
            // 切换涟漪：**无独立开关**；总关降级为「0ms 静态成功态」（反馈必须留）
            return MotionEffectDescriptor(id: id, visual: .ripple, offState: .keepFeedback,
                                          hasIndependentSwitch: false, requiresDecorationLayer: false,
                                          isGesture: false,
                                          retainedFeedback: .staticSuccess("已切换"),
                                          naturalTrigger: "「换一个版本」成功（涟漪在切换成功时播放）")
        case .t6InkGrow:
            // 墨量错峰生长：开态逐项错峰；关态「全部直接置终态，同帧出现」
            return MotionEffectDescriptor(id: id, visual: .staggeredGrow, offState: .directSwap,
                                          hasIndependentSwitch: true, requiresDecorationLayer: false,
                                          isGesture: false,
                                          naturalTrigger: "墨量页成就卡（错峰生长）")
        case .egg1CoverLiquid:
            // 封面液体流动／书脊抽出：关态「长按逻辑不注册，装饰层不创建」
            return MotionEffectDescriptor(id: id, visual: .liquidCover, offState: .noDecorationLayer,
                                          hasIndependentSwitch: true, requiresDecorationLayer: true,
                                          isGesture: true,
                                          naturalTrigger: "书架封面长按（单 case ＋ variant，不拆枚举）")
        case .egg2PinchSpine:
            // 捏合书脊视图：关态「捏合逻辑保留，无过渡直切视图」→ 触发短路但等价路径在
            return MotionEffectDescriptor(id: id, visual: .pinchSpine, offState: .shortCircuitTrigger,
                                          hasIndependentSwitch: true, requiresDecorationLayer: false,
                                          isGesture: true,
                                          naturalTrigger: "书架捏合手势（**仅书架注册**；等价路径＝视图切换条按钮）")
        case .egg3PaperPull:
            // 纸质下拉回弹：关态「装饰层不创建，下拉刷新生效」→ 触发保留、装饰层不创建
            return MotionEffectDescriptor(id: id, visual: .paperPull, offState: .noDecorationLayer,
                                          hasIndependentSwitch: true, requiresDecorationLayer: true,
                                          isGesture: true,
                                          naturalTrigger: "阅读页下拉刷新（装饰层不创建，刷新仍生效）")
        case .egg4DogEar:
            // 页角折角：关态「折角手势不注册，加书签走菜单（功能不丢）」
            return MotionEffectDescriptor(id: id, visual: .dogEar, offState: .shortCircuitTrigger,
                                          hasIndependentSwitch: true, requiresDecorationLayer: true,
                                          isGesture: true,
                                          naturalTrigger: "阅读器页角热区（加书签的等价路径在阅读设置按钮）")
        case .egg5ShakePanel:
            // 摇一摇唤书摘：关态「摇动无响应（限流一并停跑），书摘卡不出现」
            // 注册条件：仅阅读工具条展开时生效 ＋ 仅 `.adultConfirmed` 注册（DESIGN §4.1）
            return MotionEffectDescriptor(id: id, visual: .shakePanel, offState: .shortCircuitTrigger,
                                          hasIndependentSwitch: true, requiresDecorationLayer: true,
                                          isGesture: true, activation: .readingToolbarExpanded,
                                          ageGate: .adultConfirmedOnly,
                                          naturalTrigger: "摇动手机弹出随机书摘卡（纯色卡，非玻璃；与「换一个版本」是两条独立路径）")
        case .uit1ChromeToggle:
            // 工具条显隐：关态「直接显隐（仿真/双页下顶栏返回恒可达）」
            return MotionEffectDescriptor(id: id, visual: .chromeSlide, offState: .directSwap,
                                          hasIndependentSwitch: true, requiresDecorationLayer: false,
                                          isGesture: false,
                                          naturalTrigger: "**唯一入口＝点按正文中央**（单手势、无自动恢复）")
        case .uit2EdgeBack:
            // 边缘单指侧滑退出：关态「直切退出，手势仍可用」；**仅滚动/直切模式注册**
            return MotionEffectDescriptor(id: id, visual: .edgeSlide, offState: .directSwap,
                                          hasIndependentSwitch: true, requiresDecorationLayer: false,
                                          isGesture: true,
                                          registeredModes: [.none, .scroll, .vertical],
                                          naturalTrigger: "阅读页边缘单指侧滑（仿真/双页禁用，走顶栏返回）")
        }
    }

    /// 某 ID 的**曲线与时长**（DESIGN §4.1 原文口径，单一来源）。
    ///
    /// 协调器的标准动画由此派生——**不共用一个时长**（原实现对全部 13 个动效用同一个
    /// `.snappy(0.3)`，与 DESIGN 的逐 ID 曲线口径不符）。
    public static func timing(for id: MotionID) -> MotionTiming {
        switch id {   // 穷举：新增 MotionID case 不加分支即编译失败
        case .t1BookOpen:
            return MotionTiming(duration: 0.38, curve: .custom)                  // 380ms --e-open（perspective 1200；rotateY 0→-6°→0）
        case .t2VersionSwap:
            return MotionTiming(duration: 0.26, curve: .easeOut)                  // 260ms ease-out
        case .t3ThemeWipe:
            return MotionTiming(duration: 0.42, curve: .custom)                   // 420ms --e-band（径向裁剪）
        case .t4RestoreSettle:
            return MotionTiming(duration: 0.34, curve: .spring, damping: 0.78)    // 340ms spring damping .78（1.0→1.02→1.0）
        case .t5SwitchRipple:
            return MotionTiming(duration: 0.60, curve: .exponentialDecay)          // 600ms 指数衰减
        case .t6InkGrow:
            return MotionTiming(duration: 0.50, curve: .spring, damping: 0.8, stagger: 0.025)  // spring(.5,.8)；间隔 25ms
        case .egg1CoverLiquid:
            return MotionTiming(duration: 0.50, curve: .easeOut)                  // 500ms ease-out
        case .egg2PinchSpine:
            return MotionTiming(duration: 0.50, curve: .spring, damping: 0.8)     // 跟手 ＋ 松手吸附
        case .egg3PaperPull:
            return MotionTiming(duration: 0.50, curve: .spring, damping: 0.55, stagger: 0.06)  // 阻尼 .55；墨滴 3 圆错峰 60ms
        case .egg4DogEar:
            return MotionTiming(duration: 0.34, curve: .spring, damping: 0.78)    // 见 DESIGN §7 阅读器热区定义
        case .egg5ShakePanel:
            return MotionTiming(duration: 0.34, curve: .spring, damping: 0.78)    // 书摘卡弹出（高 ≤280pt）
        case .uit1ChromeToggle:
            return MotionTiming(duration: 0.25, curve: .easeOut)                  // 工具条显隐（单手势、无自动恢复）
        case .uit2EdgeBack:
            return MotionTiming(duration: 0.25, curve: .easeOut)                  // 直切 pop（手势仍可用）
        }
    }

    /// 某翻页模式下**已注册**的动效 ID 集合。
    ///
    /// UIT2 在仿真（`flip`/`curl`）下**不注册**——仿真翻页有自己的边缘行为，
    /// 且「顶栏返回恒可达」（UIT1 关态要求）不得被边缘手势抢走。
    public static func registeredIDs(in mode: PageTurnMode) -> Set<MotionID> {
        Set(all.filter { $0.registeredModes.contains(mode) }.map(\.id))
    }

    /// 某 ID 在某模式下是否已注册。
    public static func isRegistered(_ id: MotionID, in mode: PageTurnMode) -> Bool {
        descriptor(for: id).registeredModes.contains(mode)
    }
}
