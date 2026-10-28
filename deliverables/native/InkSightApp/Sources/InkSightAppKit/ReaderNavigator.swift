import Foundation
import InkSightCore

// MARK: - ReaderNavigator（跨页面打开阅读器的 App 级路由）

/// 阅读器导航请求：打开某本书的某一章，并可选地定位到某个字符偏移。
///
/// 用途（FR-024a 检索跳转）：墨量 Tab 的检索结果要能跳到书架 Tab 的阅读器，
/// 两个页面之间没有直接的视图父子关系——用 App 级路由器传一次请求。
public struct ReaderNavigationRequest: Equatable, Sendable {
    public let bookID: String
    public let chapterIndex: Int
    /// 目标字符偏移（检索命中位置）；nil ＝ 从该章开头（或已存进度）打开。
    public let charOffset: Int?

    public init(bookID: String, chapterIndex: Int, charOffset: Int? = nil) {
        self.bookID = bookID
        self.chapterIndex = chapterIndex
        self.charOffset = charOffset
    }
}

/// App 级阅读器路由器（唯一真相）。
///
/// 纪律（与 NFR-10「运行时唯一真相」同源）：
/// - **构造保证**：`shared` 是 App 级单例；需要隔离（单测）时显式传独立实例。
/// - **一次性消费**：`consume()` 取走请求并清空——避免同一请求被重复触发。
/// - 本类型只承载**意图**，不执行跳转；执行由阅读器宿主（`ShelfScreen`）负责。
public final class ReaderNavigator: @unchecked Sendable {

    /// App 级单例。
    public static let shared = ReaderNavigator()

    private var pending: ReaderNavigationRequest?
    private let lock = NSLock()

    public init() {}

    /// 请求打开阅读器（覆盖未消费的请求——后到的意图优先）。
    public func request(_ navigation: ReaderNavigationRequest) {
        lock.lock()
        pending = navigation
        lock.unlock()
        // RootTabView 用此通知切到书架 Tab；ShelfScreen onAppear 再一次性消费请求。
        NotificationCenter.default.post(name: .readerNavigationRequested, object: nil)
    }

    /// 取走待处理请求（一次性；取走后即清空）。无请求返回 nil。
    public func consume() -> ReaderNavigationRequest? {
        lock.lock(); defer { lock.unlock() }
        let value = pending
        pending = nil
        return value
    }

    /// 是否存在待处理请求（不消费）。
    public var hasPending: Bool {
        lock.lock(); defer { lock.unlock() }
        return pending != nil
    }
}

public extension Notification.Name {
    /// 检索结果请求打开阅读器（RootTabView 切到书架 Tab）。
    static let readerNavigationRequested = Notification.Name("InkSight.readerNavigationRequested")
}
