import SwiftUI
import InkSightAppKit
import InkSightCore

/// 动效运行时面板（开发包 #9／#10）：**13 个动效的真实可播实现 ＋ 真实触发点**。
///
/// 纪律：
/// - 每个触发点**一律经 `MotionCoordinator.perform(_:_:)`**——触发点不自己读设置文件、
///   也不自己判断播不播；分流由协调器按「总关／单关／系统减弱动态效果」裁决（NFR-10 单一真相）。
/// - **13 个 ID 一个不多一个不少**（顺序即 FR-030 顺序，便于逐行核对）。
/// - 面板本身 **0 玻璃**（不引用 `GlassSurface`；背景为不透明纸面）。
/// - 观感/帧率属真机项（POC-5），本面板只保证**代码路径正确**。
struct MotionRuntimeScreen: View {

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("13 个动效均为真实可播实现；触发一律经 `MotionCoordinator.perform`（不自行读设置文件）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("动效运行时 · 说明")
                }

                Section { T1BookOpenEffect() } header: { Text("T1 · 书架翻开") }
                Section { T2VersionSwapEffect() } header: { Text("T2 · 版本层翻片") }
                Section { T3ThemeWipeEffect() } header: { Text("T3 · 色带漫延") }
                Section { T4RestoreSettleEffect() } header: { Text("T4 · 位置记忆回弹（无独立开关）") }
                Section { T5SwitchRippleEffect() } header: { Text("T5 · 切换涟漪（无独立开关）") }
                Section { T6InkGrowEffect() } header: { Text("T6 · 墨量错峰生长") }
                Section { EGG1CoverLiquidEffect() } header: { Text("EGG1 · 封面液体流动／书脊抽出") }
                Section { EGG2PinchSpineEffect() } header: { Text("EGG2 · 捏合书脊视图") }
                Section { EGG3PaperPullEffect() } header: { Text("EGG3 · 纸质下拉回弹") }
                Section { EGG4DogEarEffect() } header: { Text("EGG4 · 页角折角") }
                Section { EGG5ShakePanelEffect() } header: { Text("EGG5 · 摇一摇唤面板") }
                Section { UIT1ChromeToggleEffect() } header: { Text("UIT1 · 工具条显隐") }
                Section { UIT2EdgeBackEffect() } header: { Text("UIT2 · 边缘单指侧滑退出") }
            }
            .navigationTitle("动效运行时")
        }
    }
}
