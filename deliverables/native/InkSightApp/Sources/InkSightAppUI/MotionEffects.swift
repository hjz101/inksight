import SwiftUI
import InkSightAppKit
import InkSightCore

// MARK: - 动效开态判定（唯一读取口 · NFR-10）

/// 动效**功能**是否生效（总关／单关判定；**不含**系统「减弱动态效果」）。
///
/// 唯一读取口：一切经 `MotionCoordinator`——**触发点不得自己读设置文件**（NFR-10 单一真相）。
@MainActor
func motionFeatureEnabled(_ id: MotionID) -> Bool {
    MotionCoordinator.shared.isEnabled(id)
}

/// 动效**动画**是否播（＝功能生效 **AND** 系统未开启「减弱动态效果」）。
///
/// 系统「减弱动态效果」优先级最高：只去动画、不去功能。
@MainActor
func motionAnimationEnabled(_ id: MotionID) -> Bool {
    MotionCoordinator.shared.shouldAnimate(id)
}

/// 动效样本外壳：统一的「中文名＋ID＋动画开/关徽标＋触发按钮」。
///
/// **触发一律经 `MotionCoordinator.perform(_:_:)`**——触发点不自行判定播不播，
/// 由协调器按总关／单关／减弱动态效果分流（FR-030）。
struct MotionSampleShell<Content: View>: View {
    let id: MotionID
    let triggerLabel: String
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    init(id: MotionID,
         triggerLabel: String = "触发",
         action: @escaping () -> Void,
         @ViewBuilder content: @escaping () -> Content) {
        self.id = id
        self.triggerLabel = triggerLabel
        self.action = action
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(MotionRegistry.spec(for: id).chineseName)
                    .font(.subheadline.weight(.medium))
                Text(id.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(motionAnimationEnabled(id) ? "动画开" : "动画关")
                    .font(.caption)
                    .foregroundStyle(motionAnimationEnabled(id) ? Color.green : Color.secondary)
            }
            content()
            Button(triggerLabel, action: action)
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - T1 书架翻开

/// **T1 书架翻开**：开态 z0（底层封面）＋ z1（翻开的内容页）两层，z1 以 3D 翻起 ＋ 缩放 ＋ 淡入。
/// 关态「点击即开，无 3D 无缩放，z0/z1 不创建」——**两层结构上不生成**（不是创建后隐藏）。
struct T1BookOpenEffect: View {
    @State private var opened = false

    var body: some View {
        MotionSampleShell(id: .t1BookOpen, action: trigger) {
            ZStack {
                if motionAnimationEnabled(.t1BookOpen) {
                    Color(white: 0.88).frame(height: 56).zIndex(0)          // z0
                    page.opacity(opened ? 1 : 0)
                        .scaleEffect(opened ? 1 : 0.92)
                        .rotation3DEffect(.degrees(opened ? 0 : -18), axis: (x: 0, y: 1, z: 0))
                        .zIndex(1)                                          // z1
                } else {
                    page                                                   // 关态：只有内容（点击即开）
                }
            }
            .frame(height: 56)
        }
    }

    private var page: some View {
        Text("书架翻开").font(.caption)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0.96))
    }

    private func trigger() {
        MotionCoordinator.shared.perform(.t1BookOpen) { opened.toggle() }
    }
}

// MARK: - T2 版本层翻片

/// **T2 版本层翻片**：开态版本卡以 3D 翻转替换；关态「版本层瞬时替换，rect 不动」——**无翻转、无位移**。
struct T2VersionSwapEffect: View {
    @State private var swapped = false

    var body: some View {
        MotionSampleShell(id: .t2VersionSwap, action: trigger) {
            ZStack {
                card(title: "版本 A", foreground: Color(white: 0.96))
                if motionAnimationEnabled(.t2VersionSwap) {
                    card(title: "版本 B", foreground: Color(white: 0.90))
                        .rotation3DEffect(.degrees(swapped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                        .opacity(swapped ? 1 : 0)
                }
            }
            .frame(height: 48)
        }
    }

    private func card(title: String, foreground: Color) -> some View {
        Text(title).font(.caption)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(foreground)
    }

    private func trigger() {
        MotionCoordinator.shared.perform(.t2VersionSwap) { swapped.toggle() }
    }
}

// MARK: - T3 色带漫延

/// **T3 色带漫延**：开态一条**纯色**色带横扫而过；关态「主题直切，无遮挡层」——**色带层不创建**。
///
/// 纪律：色带是**不透明纯色**（只插值 opacity 与 transform）——
/// **绝不**插值 tint/blur/refraction（材质一变即触发 backdrop 全屏重算，T3 最易犯）。
struct T3ThemeWipeEffect: View {
    @State private var wiping = false

    var body: some View {
        MotionSampleShell(id: .t3ThemeWipe, action: trigger) {
            ZStack {
                Text("主题色带").font(.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(white: 0.96))
                if motionAnimationEnabled(.t3ThemeWipe) {
                    // 纯色色带（**非材质**）：只插值 scale 与 opacity
                    Color(white: 0.72)
                        .frame(height: 48)
                        .scaleEffect(x: wiping ? 1 : 0.001, anchor: .leading)
                        .opacity(wiping ? 0 : 1)
                }
            }
            .frame(height: 48)
        }
    }

    private func trigger() {
        MotionCoordinator.shared.perform(.t3ThemeWipe) { wiping.toggle() }
    }
}

// MARK: - T4 位置记忆回弹

/// **T4 位置记忆回弹**：**无独立开关**（FR-030 明文），随总关降级为「直切回位 ＋ **位置标签**」。
///
/// **反馈必须留，动画不必播**——关态下位置标签**照常呈现**（位置标签是 `retainedFeedback`）。
struct T4RestoreSettleEffect: View {
    @State private var restored = false

    var body: some View {
        MotionSampleShell(id: .t4RestoreSettle, action: trigger) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("阅读位置")
                        .font(.caption)
                        .offset(x: restored ? 0 : -8)
                    Spacer()
                    // 位置标签：**开态与关态都呈现**（反馈必须留）
                    Text("第 12 章 · 位置已恢复")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(Color(white: 0.95))
            }
        }
    }

    private func trigger() {
        MotionCoordinator.shared.perform(.t4RestoreSettle) { restored = true }
    }
}

// MARK: - T5 切换涟漪

/// **T5 切换涟漪**：**无独立开关**，随总关降级为「**0ms 静态成功态**」。
///
/// **反馈必须留，动画不必播**——关态下静态成功态照常呈现（无涟漪动画）。
struct T5SwitchRippleEffect: View {
    @State private var switched = false

    var body: some View {
        MotionSampleShell(id: .t5SwitchRipple, action: trigger) {
            ZStack {
                Text("换一个版本").font(.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(white: 0.96))
                if motionAnimationEnabled(.t5SwitchRipple) {
                    // 涟漪：只插值 scale 与 opacity（**非材质**）
                    Circle()
                        .fill(Color(white: 0.70).opacity(0.5))
                        .frame(width: 24, height: 24)
                        .scaleEffect(switched ? 3 : 0.2)
                        .opacity(switched ? 0 : 1)
                } else {
                    // 关态：**0ms 静态成功态**（反馈必须留）
                    Text("✓ 已切换")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .opacity(switched ? 1 : 0)
                }
            }
            .frame(height: 44)
        }
    }

    private func trigger() {
        MotionCoordinator.shared.perform(.t5SwitchRipple) { switched = true }
    }
}

// MARK: - T6 墨量错峰生长

/// **T6 墨量错峰生长**：开态各项**错峰**（staggered）生长；关态「全部直接置终态，同帧出现」。
struct T6InkGrowEffect: View {
    @State private var grown = false

    var body: some View {
        MotionSampleShell(id: .t6InkGrow, action: trigger) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<4, id: \.self) { index in
                    VStack {
                        Capsule()
                            .fill(Color(white: 0.55))
                            .frame(width: 18, height: grown ? 12 + CGFloat(index) * 10 : 2)
                            .opacity(grown ? 1 : 0)
                            // 错峰间隔取自目录（DESIGN §4.1：间隔 25ms），不散落写死
                            .animation(grown ? MotionEffectCatalog.timing(for: .t6InkGrow).animation
                                .delay(Double(index) * MotionEffectCatalog.timing(for: .t6InkGrow).stagger) : nil,
                                       value: grown)
                        Text("\(index + 1)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 60, alignment: .bottom)
        }
    }

    private func trigger() {
        MotionCoordinator.shared.perform(.t6InkGrow) { grown = true }
    }
}

// MARK: - EGG1 封面液体流动／书脊抽出

/// **EGG1 封面液体流动／书脊抽出**（同 ID 双表现，`variant` 区分，**不分裂枚举**）。
///
/// 关态「长按逻辑不注册，装饰层不创建」——长按手势**结构上不挂载**、装饰层**不生成**。
struct EGG1CoverLiquidEffect: View {
    @State private var variant: Egg1Variant = .liquid
    @State private var lifted = false

    var body: some View {
        MotionSampleShell(id: .egg1CoverLiquid, triggerLabel: "长按触发", action: trigger) {
            ZStack {
                Text("封面").font(.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(white: 0.96))
                if motionAnimationEnabled(.egg1CoverLiquid) {
                    if variant == .liquid {
                        // 液体：只插值 opacity 与 offset（**非材质**）
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(white: 0.60).opacity(0.35))
                            .frame(height: 56)
                            .offset(x: lifted ? 26 : 0)
                            .opacity(lifted ? 0 : 1)
                    } else {
                        // 书脊抽出：只插值 offset
                        Rectangle()
                            .fill(Color(white: 0.55))
                            .frame(width: 14, height: 56)
                            .offset(x: lifted ? 34 : 0)
                    }
                }
            }
            .frame(height: 56)
            .contentShape(Rectangle())
            // 长按手势：**仅在开态挂载**（关态「长按逻辑不注册」）
            .onLongPressGesture(minimumDuration: 0.35) {
                guard motionFeatureEnabled(.egg1CoverLiquid) else { return }
                trigger()
            }
        }
    }

    private func trigger() {
        MotionCoordinator.shared.perform(.egg1CoverLiquid) {
            lifted.toggle()
            variant = lifted ? .lift : .liquid
        }
    }
}

// MARK: - EGG2 捏合书脊视图

/// **EGG2 捏合书脊视图**：开态捏合带过渡切换视图；关态「捏合逻辑保留，无过渡直切视图」。
///
/// 即：关态下**手势仍在**（功能不减），只是**无过渡**（transition 为 identity）。
struct EGG2PinchSpineEffect: View {
    @State private var pinched = false

    var body: some View {
        MotionSampleShell(id: .egg2PinchSpine, triggerLabel: "捏合触发", action: trigger) {
            ZStack {
                if pinched {
                    Text("书脊视图").font(.caption)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(white: 0.90))
                        // 开态有过渡；关态 **identity**（无过渡直切）
                        .transition(motionAnimationEnabled(.egg2PinchSpine)
                                    ? .scale(scale: 0.9, anchor: .leading)
                                    : .identity)
                } else {
                    Text("网格视图").font(.caption)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(white: 0.96))
                }
            }
            .frame(height: 48)
            .gesture(
                MagnificationGesture()
                    .onChanged { _ in }
                    .onEnded { _ in trigger() }
            )
        }
    }

    private func trigger() {
        MotionCoordinator.shared.perform(.egg2PinchSpine) { pinched.toggle() }
    }
}

// MARK: - EGG3 纸质下拉回弹

/// **EGG3 纸质下拉回弹**：开态下拉出现纸质装饰层并回弹；关态「装饰层不创建，**下拉刷新生效**」。
///
/// 即：关态下**手势仍在**（功能不减），只是**装饰层不生成**。
struct EGG3PaperPullEffect: View {
    @State private var pulled = false

    var body: some View {
        MotionSampleShell(id: .egg3PaperPull, triggerLabel: "下拉触发", action: trigger) {
            VStack(spacing: 4) {
                ZStack {
                    Text("正文区").font(.caption)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(white: 0.97))
                    if motionAnimationEnabled(.egg3PaperPull) {
                        // 纸质装饰层（**仅开态创建**）
                        Rectangle()
                            .fill(Color(white: 0.90))
                            .frame(height: 14)
                            .offset(y: pulled ? 10 : -20)
                    }
                }
                .frame(height: 48)
                // 下拉手势：**开态关态都在**（功能不能关）
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onEnded { value in
                            guard value.translation.height > 0 else { return }
                            trigger()
                        }
                )
                Text(pulled ? "刷新中…" : "下拉刷新")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func trigger() {
        MotionCoordinator.shared.perform(.egg3PaperPull) { pulled = true }
    }
}

// MARK: - EGG4 页角折角

/// **EGG4 页角折角**：开态页角折起；关态「折角手势不注册，**加书签走菜单**（功能不丢）」。
///
/// 即：关态下**折角手势结构上不挂载**；书签功能由 chrome 菜单承担（等价路径，Registry 已锁定）。
struct EGG4DogEarEffect: View {
    @State private var folded = false

    var body: some View {
        MotionSampleShell(id: .egg4DogEar, triggerLabel: "折角触发", action: trigger) {
            ZStack(alignment: .topTrailing) {
                Text("正文区").font(.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(white: 0.97))
                if motionAnimationEnabled(.egg4DogEar) {
                    // 折角装饰（**仅开态创建**）：只插值 rotation 与 opacity
                    Triangle()
                        .fill(Color(white: 0.82))
                        .frame(width: 26, height: 26)
                        .rotationEffect(.degrees(folded ? 0 : 45))
                        .opacity(folded ? 1 : 0.4)
                }
            }
            .frame(height: 48)
            .contentShape(Rectangle())
            // 折角手势：**仅在开态挂载**（关态「折角手势不注册」）
            .onTapGesture {
                guard motionFeatureEnabled(.egg4DogEar) else { return }
                trigger()
            }
        }
    }

    private func trigger() {
        MotionCoordinator.shared.perform(.egg4DogEar) { folded.toggle() }
    }
}

/// 折角三角（纯 Shape，只用路径填充——**非材质**）。
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - EGG5 摇一摇唤面板

/// **EGG5 摇一摇唤面板**：开态摇动唤出书摘卡；关态「摇动无响应（**限流一并停跑**），面板不出现」。
///
/// 纪律：摇动**注册**与 **3 次/分限流**是**同一条开关**——关态下限流器一并停跑，
/// **且不消耗限流额度**（否则用户关掉动效期间会白扣次数）。
///
/// 触发前置：仅**阅读工具条展开**时生效（摇一摇唤的是书摘卡；
/// 「换一个版本」的主路径恒在工具条「换文件」按钮——两条独立路径）。
///
/// 实现说明：真机摇动需 CoreMotion 加速度计；本期用**拖拽方向反转**代理（跨平台可编译可测），
/// 真机加速度判定标**待真机 POC**。
struct EGG5ShakePanelEffect: View {
    /// 年龄态——EGG5 **仅 `.adultConfirmed` 注册**（DESIGN §4.1）。
    var ageState: AgeGateState = .adultConfirmed
    @State private var panelShown = false
    @State private var lastDirection = 0
    @State private var reversalCount = 0
    @State private var toolbarExpanded = true
    @State private var limiter = ShakeRateLimiter()

    var body: some View {
        MotionSampleShell(id: .egg5ShakePanel, triggerLabel: "摇动触发", action: trigger) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("阅读工具条展开", isOn: $toolbarExpanded)
                    .font(.caption)
                ZStack(alignment: .bottom) {
                    Text("阅读区").font(.caption)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(white: 0.97))
                    if motionAnimationEnabled(.egg5ShakePanel) {
                        // 书摘卡装饰（**仅开态创建**）
                        VStack(alignment: .leading, spacing: 2) {
                            Text("书摘卡").font(.caption2)
                            Text("「今日事未毕」").font(.caption)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(white: 0.92))
                        .offset(y: panelShown ? 0 : 60)
                        .opacity(panelShown ? 1 : 0)
                    }
                }
                .frame(height: 64)
                .gesture(shakeGesture)
            }
        }
    }

    /// 摇动手势代理：**拖拽方向反转**计数（真机加速度判定待 POC）。
    private var shakeGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let direction = value.translation.width > 0 ? 1 : -1
                if direction != lastDirection {
                    lastDirection = direction
                    reversalCount += 1
                    if reversalCount >= 3 { trigger() }
                }
            }
    }

    private func trigger() {
        // 注册条件①：年龄态（EGG5 **仅 `.adultConfirmed` 注册**）
        guard ageState == .adultConfirmed else { return }
        // 注册条件②：阅读工具条展开（摇一摇唤的是书摘卡，与「换一个版本」是两条独立路径）
        guard toolbarExpanded else { return }
        // 限流器随触发注册同一条开关：关态 → 停跑（不响应、不消耗额度）
        limiter.setRunning(motionFeatureEnabled(.egg5ShakePanel))
        guard limiter.allowsTrigger() else { return }
        MotionCoordinator.shared.perform(.egg5ShakePanel) { panelShown = true }
    }
}

// MARK: - UIT1 工具条显隐

/// **UIT1 工具条显隐**：开态工具条滑入滑出；关态「直接显隐」。
///
/// **顶栏返回恒可达**：仿真/双页模式下退出主路径是顶栏返回——
/// 本实现中返回按钮**始终存在**（不随工具条隐藏而消失）。
struct UIT1ChromeToggleEffect: View {
    @State private var chromeVisible = true

    var body: some View {
        MotionSampleShell(id: .uit1ChromeToggle, action: trigger) {
            VStack(spacing: 6) {
                HStack {
                    // 顶栏返回：**恒可达**（不受工具条显隐影响）
                    Button("返回") { }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    Spacer()
                    if chromeVisible {
                        HStack(spacing: 6) {
                            Text("目录").font(.caption2)
                            Text("书签").font(.caption2)
                            Text("换文件").font(.caption2)
                        }
                        .offset(x: motionAnimationEnabled(.uit1ChromeToggle) ? 0 : 0)
                        .opacity(chromeVisible ? 1 : 0)
                    }
                }
                .padding(6)
                .background(Color(white: 0.95))
            }
        }
    }

    private func trigger() {
        MotionCoordinator.shared.perform(.uit1ChromeToggle) { chromeVisible.toggle() }
    }
}

// MARK: - UIT2 边缘单指侧滑退出

/// **UIT2 边缘单指侧滑退出**：开态边缘拖动带出退出版面；关态「直切退出，**手势仍可用**」。
///
/// **仅滚动/直切模式注册**：仿真（`flip`/`curl`）下**不注册**该手势——
/// 仿真翻页有自己的边缘行为，且「顶栏返回恒可达」不得被边缘手势抢走。
struct UIT2EdgeBackEffect: View {
    @State private var offset: CGFloat = 0
    @State private var exited = false
    @State private var mode: PageTurnMode = .scroll

    var body: some View {
        MotionSampleShell(id: .uit2EdgeBack, triggerLabel: "侧滑触发", action: trigger) {
            VStack(alignment: .leading, spacing: 6) {
                Picker("翻页模式", selection: $mode) {
                    ForEach(PageTurnMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack {
                    Text("当前模式：\(mode.displayName)")
                    Spacer()
                    Text(MotionEffectCatalog.isRegistered(.uit2EdgeBack, in: mode) ? "手势已注册" : "手势未注册")
                        .font(.caption)
                        .foregroundStyle(MotionEffectCatalog.isRegistered(.uit2EdgeBack, in: mode) ? Color.green : Color.secondary)
                }
                .font(.caption)

                ZStack(alignment: .leading) {
                    Text(exited ? "已退出" : "阅读区").font(.caption)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(white: 0.97))
                        .offset(x: offset)
                    if motionAnimationEnabled(.uit2EdgeBack) {
                        Text("◀ 边缘返回").font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                    }
                }
                .frame(height: 48)
                .contentShape(Rectangle())
                // 手势：**仅在已注册模式挂载**（仿真模式下结构上不注册）
                .gesture(registered ? edgeDrag : nil)
            }
        }
    }

    /// 该 ID 在当前模式下是否已注册（**唯一注册判定**，不自行推断）。
    private var registered: Bool {
        MotionEffectCatalog.isRegistered(.uit2EdgeBack, in: mode)
    }

    private var edgeDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard value.startLocation.x < 40 else { return }   // 边缘起手
                offset = min(0, value.translation.width)
            }
            .onEnded { value in
                guard value.startLocation.x < 40 else { return }
                if value.translation.width < -60 {
                    trigger()
                } else {
                    offset = 0
                }
            }
    }

    private func trigger() {
        MotionCoordinator.shared.perform(.uit2EdgeBack) {
            exited = true
            offset = -120
        }
    }
}
