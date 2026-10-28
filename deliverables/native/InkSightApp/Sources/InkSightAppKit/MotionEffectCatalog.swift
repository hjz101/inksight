import Foundation

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
    case shakePanel      // EGG5 摇一摇唤面板
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
    /// EGG5 依据：摇一摇唤的是**书摘卡**；「换一个版本」的主路径恒在阅读工具条「换文件」按钮——
    /// 摇一摇**不**承担版本切换，故工具条未展开时摇动不唤面板。
    case readingToolbarExpanded
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

    public init(id: MotionID,
                visual: MotionVisual,
                offState: MotionOffState,
                hasIndependentSwitch: Bool,
                requiresDecorationLayer: Bool,
                isGesture: Bool,
                activation: MotionActivation = .anytime,
                interpolatesMaterial: Bool = false,
                registeredModes: Set<PageTurnMode> = Set(PageTurnMode.allCases),
                retainedFeedback: MotionRetainedFeedback? = nil) {
        self.id = id
        self.visual = visual
        self.offState = offState
        self.hasIndependentSwitch = hasIndependentSwitch
        self.requiresDecorationLayer = requiresDecorationLayer
        self.isGesture = isGesture
        self.activation = activation
        self.interpolatesMaterial = interpolatesMaterial
        self.registeredModes = registeredModes
        self.retainedFeedback = retainedFeedback
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
                                          isGesture: false)
        case .t2VersionSwap:
            // 版本层翻片：开态 3D 翻片；关态「版本层瞬时替换，rect 不动」
            return MotionEffectDescriptor(id: id, visual: .cardFlip, offState: .directSwap,
                                          hasIndependentSwitch: true, requiresDecorationLayer: false,
                                          isGesture: false)
        case .t3ThemeWipe:
            // 色带漫延：开态纯色色带扫过；关态「主题直切，无遮挡层」（色带层不创建）
            return MotionEffectDescriptor(id: id, visual: .colorBandWipe, offState: .noDecorationLayer,
                                          hasIndependentSwitch: true, requiresDecorationLayer: true,
                                          isGesture: false)
        case .t4RestoreSettle:
            // 位置记忆回弹：**无独立开关**；总关降级为「直切回位＋位置标签」（反馈必须留）
            return MotionEffectDescriptor(id: id, visual: .settleSpring, offState: .keepFeedback,
                                          hasIndependentSwitch: false, requiresDecorationLayer: false,
                                          isGesture: false,
                                          retainedFeedback: .positionLabel("第 12 章 · 位置已恢复"))
        case .t5SwitchRipple:
            // 切换涟漪：**无独立开关**；总关降级为「0ms 静态成功态」（反馈必须留）
            return MotionEffectDescriptor(id: id, visual: .ripple, offState: .keepFeedback,
                                          hasIndependentSwitch: false, requiresDecorationLayer: false,
                                          isGesture: false,
                                          retainedFeedback: .staticSuccess("已切换"))
        case .t6InkGrow:
            // 墨量错峰生长：开态逐项错峰；关态「全部直接置终态，同帧出现」
            return MotionEffectDescriptor(id: id, visual: .staggeredGrow, offState: .directSwap,
                                          hasIndependentSwitch: true, requiresDecorationLayer: false,
                                          isGesture: false)
        case .egg1CoverLiquid:
            // 封面液体流动／书脊抽出：关态「长按逻辑不注册，装饰层不创建」
            return MotionEffectDescriptor(id: id, visual: .liquidCover, offState: .noDecorationLayer,
                                          hasIndependentSwitch: true, requiresDecorationLayer: true,
                                          isGesture: true)
        case .egg2PinchSpine:
            // 捏合书脊视图：关态「捏合逻辑保留，无过渡直切视图」→ 触发短路但等价路径在
            return MotionEffectDescriptor(id: id, visual: .pinchSpine, offState: .shortCircuitTrigger,
                                          hasIndependentSwitch: true, requiresDecorationLayer: false,
                                          isGesture: true)
        case .egg3PaperPull:
            // 纸质下拉回弹：关态「装饰层不创建，下拉刷新生效」→ 触发保留、装饰层不创建
            return MotionEffectDescriptor(id: id, visual: .paperPull, offState: .noDecorationLayer,
                                          hasIndependentSwitch: true, requiresDecorationLayer: true,
                                          isGesture: true)
        case .egg4DogEar:
            // 页角折角：关态「折角手势不注册，加书签走菜单（功能不丢）」
            return MotionEffectDescriptor(id: id, visual: .dogEar, offState: .shortCircuitTrigger,
                                          hasIndependentSwitch: true, requiresDecorationLayer: true,
                                          isGesture: true)
        case .egg5ShakePanel:
            // 摇一摇唤面板：关态「摇动无响应（限流一并停跑），面板不出现」
            // 触发前置：仅阅读工具条展开时生效（主路径恒在工具条「换文件」按钮）
            return MotionEffectDescriptor(id: id, visual: .shakePanel, offState: .shortCircuitTrigger,
                                          hasIndependentSwitch: true, requiresDecorationLayer: true,
                                          isGesture: true, activation: .readingToolbarExpanded)
        case .uit1ChromeToggle:
            // 工具条显隐：关态「直接显隐（仿真/双页下顶栏返回恒可达）」
            return MotionEffectDescriptor(id: id, visual: .chromeSlide, offState: .directSwap,
                                          hasIndependentSwitch: true, requiresDecorationLayer: false,
                                          isGesture: false)
        case .uit2EdgeBack:
            // 边缘单指侧滑退出：关态「直切退出，手势仍可用」；**仅滚动/直切模式注册**
            return MotionEffectDescriptor(id: id, visual: .edgeSlide, offState: .directSwap,
                                          hasIndependentSwitch: true, requiresDecorationLayer: false,
                                          isGesture: true,
                                          registeredModes: [.none, .scroll, .vertical])
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
