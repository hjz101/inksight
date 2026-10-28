import Foundation
import Combine
import InkSightCore

// MARK: - ReaderLayout（阅读容器尺寸的**单一来源**）

/// 阅读容器尺寸（**单一来源**，开发包 #10）。
///
/// **缺口背景**：`TypographySignature` 含 `containerSize` —— 设置页与阅读器若用不同尺寸，
/// 签名就不同；即使已共用同一个 `PaginationCoordinator`（NFR-11），两端缓存也**互不命中**
/// （同一本书排两遍、白排一遍，「共享协调器」的收益无法兑现）。
///
/// **因此容器尺寸必须只有一个来源**——本对象：
/// - 阅读器实测后回报**真实尺寸**；
/// - 设置页与阅读器**都从本对象读取** ⇒ 两端签名必然一致 ⇒ 缓存真正互通；
/// - `currentSignature(typography:)` 是两端**共用的签名入口**，杜绝任何一端另算一套。
///
/// **不得为此引入第二套尺寸常量**：种子值取既有的 `ReaderEngine.defaultContainerSize`，
/// 之后一律由实测值覆盖。
///
/// 线程：所有写入发生在主线程（阅读器布局回调）。
public final class ReaderLayout: ObservableObject, @unchecked Sendable {

    /// App 级单例（**构造保证**：不传参即得单例，避免「记得传 `.shared`」式的约定纪律）。
    public static let shared = ReaderLayout()

    /// 当前正文容器尺寸。
    @Published public private(set) var containerSize: CGSize

    /// 当前屏幕缩放（进 `TypographySignature`）。
    @Published public private(set) var screenScale: Double

    public init(containerSize: CGSize = ReaderEngine.defaultContainerSize, screenScale: Double = 1.0) {
        self.containerSize = containerSize
        self.screenScale = screenScale
    }

    /// 阅读器实测后回报真实尺寸（主线程调用；非法尺寸被忽略）。
    public func update(containerSize: CGSize, screenScale: Double) {
        guard containerSize.width > 0, containerSize.height > 0 else { return }
        if self.containerSize != containerSize { self.containerSize = containerSize }
        if self.screenScale != screenScale { self.screenScale = screenScale }
    }

    /// 当前排版签名（**设置页与阅读器共用的唯一签名入口**）。
    ///
    /// 两端都调本方法 ⇒ 签名必然一致 ⇒ 同一本书在不同页面重排时**命中同一套锚点缓存**。
    public func currentSignature(typography: ReaderTypography,
                                 kinsoku: Kinsoku = .v1) -> TypographySignature {
        TypographySignature(typography: typography,
                             containerSize: containerSize,
                             screenScale: screenScale,
                             kinsokuVersion: kinsoku.version)
    }
}
