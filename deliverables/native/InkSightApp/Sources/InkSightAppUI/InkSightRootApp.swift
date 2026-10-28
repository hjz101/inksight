import SwiftUI
import InkSightAppKit

// MARK: - 4 Tab 骨架（App 入口在 executableTarget InkSightAppMain；
// 库目标里的 @main 会与 swift test 的 runner _main 重复链接——SPM 链接层事实）

public struct RootTabView: View {
    public let ageState: AgeGateState
    public let variant: BuildVariant
    public let onOpenReader: () -> Void

    /// 数据层（开发包 #3）：书架仓库。骨架期默认空仓库；发行版由 App 注入真实实例。
    /// （`ReadingProgressStore` 作为可落盘的进度模型已交付并由单测覆盖；骨架期续读锚点经 `BookShelfItem.lastReadAnchor` 承载。）
    private let bookShelf: BookShelfStore
    /// 本地检索仓库（FR-024a）：App 级单例（索引跨页面复用）；初始化失败则为 nil（诚实空态）。
    private let searchStore: LocalSearchStore?
    @State private var selectedTab = 0

    /// 系统「减弱动态效果」——**优先级最高**：开启时任何动效都不播（但**功能不减**）。
    /// 同步到唯一动画入口（`MotionCoordinator`），由它统一裁决（FR-030）。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(ageState: AgeGateState, variant: BuildVariant, onOpenReader: @escaping () -> Void) {
        // FR-024a：App 级共享本地 FTS 索引；创建失败则 nil，检索页显示诚实空态。
        self.init(ageState: ageState, variant: variant, onOpenReader: onOpenReader,
                  bookShelf: BookShelfStore(), searchStore: try? LocalSearchStore())
    }

    init(ageState: AgeGateState, variant: BuildVariant, onOpenReader: @escaping () -> Void,
         bookShelf: BookShelfStore, searchStore: LocalSearchStore? = nil) {
        self.ageState = ageState
        self.variant = variant
        self.onOpenReader = onOpenReader
        self.bookShelf = bookShelf
        self.searchStore = searchStore
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            DiscoveryScreen(ageState: ageState, variant: variant)
                .tabItem { Label("发现", systemImage: "sparkles") }
                .tag(0)
            ShelfScreen(bookShelf: bookShelf, onOpenReader: onOpenReader, searchStore: searchStore)
                .tabItem { Label("书架", systemImage: "books.vertical") }
                .tag(1)
            InkScreen(bookShelf: bookShelf, searchStore: searchStore)
                .tabItem { Label("墨量", systemImage: "drop") }
                .tag(2)
            MeScreen(ageState: ageState, variant: variant, bookShelf: bookShelf)
                .tabItem { Label("我", systemImage: "person") }
                .tag(3)
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerNavigationRequested)) { _ in
            // 检索结果来自墨量 Tab：先切到书架，ShelfScreen onAppear/通知消费请求。
            selectedTab = 1
        }
        // 系统「减弱动态效果」同步到唯一动画入口（优先级最高：只去动画不去功能）
        .onAppear { MotionCoordinator.shared.systemReduceMotion = reduceMotion }
        .onChange(of: reduceMotion) { _, newValue in
            MotionCoordinator.shared.systemReduceMotion = newValue
        }
    }
}
