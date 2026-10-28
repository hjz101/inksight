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

    public init(ageState: AgeGateState, variant: BuildVariant, onOpenReader: @escaping () -> Void) {
        self.init(ageState: ageState, variant: variant, onOpenReader: onOpenReader,
                  bookShelf: BookShelfStore())
    }

    init(ageState: AgeGateState, variant: BuildVariant, onOpenReader: @escaping () -> Void,
         bookShelf: BookShelfStore) {
        self.ageState = ageState
        self.variant = variant
        self.onOpenReader = onOpenReader
        self.bookShelf = bookShelf
    }

    public var body: some View {
        TabView {
            DiscoveryScreen(ageState: ageState, variant: variant)
                .tabItem { Label("发现", systemImage: "sparkles") }
            ShelfScreen(bookShelf: bookShelf, onOpenReader: onOpenReader)
                .tabItem { Label("书架", systemImage: "books.vertical") }
            InkScreen(bookShelf: bookShelf)
                .tabItem { Label("墨量", systemImage: "drop") }
            MeScreen(ageState: ageState, variant: variant)
                .tabItem { Label("我", systemImage: "person") }
        }
    }
}
