import SwiftUI
import InkSightAppKit
import InkSightAppUI

/// App 入口（executableTarget：库目标里的 @main 会与 swift test 的 runner _main 冲突，
/// 这是 SPM 的链接层事实，不是风格问题）。
@main
struct InkSightRootApp: App {
    var body: some Scene { WindowGroup { RootView() } }
}

/// 根视图：同层切换（A 档：关闭态零动画；不用系统 push/sheet/zoom——时长由系统控制，无法归零）。
struct RootView: View {
    /// 构建变体（发行版由发行配置切换；骨架期固定 research 以演示在线矩阵）。
    private let variant: BuildVariant = .research
    /// 年龄态注入点：本期骨架固定值，**不提供任何界面切换控件**（切换/绕过路径不存在）。
    /// 发行版由 DeclaredAgeRange 决定（fail-closed：拒答→保守态，见架构 v2.2）。
    private let ageState: AgeGateState = .adultConfirmed
    @State private var readerActive = false

    /// 演示阅读引擎：注入公有领域示例章节（确定性 Demo 路径，不走真实文件导入）。
    /// 静态初始化一次，避免每次 body 重算排版。
    private static let sampleEngine = ReaderEngine(
        bookID: SampleChapter.bookID, chapterID: SampleChapter.chapterID, chapterText: SampleChapter.text
    )

    var body: some View {
        ZStack {
            if readerActive {
                ReaderSurfaceView(
                    engine: RootView.sampleEngine,
                    onExit: { MotionCoordinator.shared.perform(.uit2EdgeBack) { readerActive = false } }
                )
                .transition(.identity)
            } else {
                RootTabView(ageState: ageState, variant: variant,
                            onOpenReader: { MotionCoordinator.shared.perform(.t1BookOpen) { readerActive = true } })
                    .transition(.identity)
            }
        }
        // 启动即把持久化的动效开关应用到唯一动画入口（开发包 #7）。
        // 不做这一步的话，「持久化」只是落盘不生效＝不诚实：用户关了某 ID，重启后又自己播回来。
        .onAppear { MotionCoordinator.shared.apply(MotionSettingsStore().load()) }
    }
}
