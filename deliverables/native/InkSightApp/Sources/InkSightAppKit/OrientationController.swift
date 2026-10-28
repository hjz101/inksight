import Foundation

// MARK: - OrientationController（FR-037 阅读器锁竖屏）

/// 屏幕方向控制（FR-037）：**仅阅读器锁竖屏**，其他界面不受限。
///
/// 契约（PRD FR-037 原文）：
/// - 仅阅读器锁竖屏；其他界面不受限；
/// - `Info.plist` ＋ `supportedInterfaceOrientationsFor`；
/// - 切换用 `setNeedsUpdateOfSupportedInterfaceOrientations()`；
/// - 理由：仿真/双页几何以固定宽高为参数、`containerSize` 档位收敛、长读横屏无收益。
///
/// **职责边界**：本类型只承载**状态与通知**（纯逻辑、可测、跨平台）——
/// 实际的 UIKit 方向查询由 UI 层的宿主控制器读取 `allowedOrientationMask`。
public final class OrientationController: @unchecked Sendable {

    /// App 级单例（构造保证，与 NFR-13 同源）。
    public static let shared = OrientationController()

    private let lock = NSLock()
    private var _isReaderPortraitLocked = false

    public init() {}

    /// 阅读器是否处于「锁竖屏」状态。
    public var isReaderPortraitLocked: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isReaderPortraitLocked
    }

    /// 进入阅读器：锁竖屏。调用方：`ReaderSurfaceView.onAppear`。
    public func lockReaderToPortrait() {
        setLocked(true)
    }

    /// 退出阅读器：解锁。调用方：`ReaderSurfaceView.onDisappear`。
    public func unlockAfterReader() {
        setLocked(false)
    }

    /// 当前允许的界面方向掩码（供 UI 层 `supportedInterfaceOrientationsFor` 读取）。
    ///
    /// 数值与 UIKit 语义一致：portrait = 1<<1 = 2，landscapeRight = 1<<3 = 8，
    /// landscapeLeft = 1<<4 = 16。用 `UInt` 表达以避免 Kit 层依赖 UIKit 类型。
    public var allowedOrientationMask: UInt {
        isReaderPortraitLocked ? Self.portraitMask : Self.allSupportedMask
    }

    /// 仅竖屏。
    public static let portraitMask: UInt = 2
    /// 竖屏 ＋ 左右横屏（其他界面允许）。
    public static let allSupportedMask: UInt = 2 | 8 | 16

    // MARK: - 内部

    private func setLocked(_ value: Bool) {
        lock.lock()
        let changed = _isReaderPortraitLocked != value
        _isReaderPortraitLocked = value
        lock.unlock()
        guard changed else { return }
        // FR-037：切换后须让系统重新查询 supportedInterfaceOrientationsFor。
        // 通知 UI 层执行 `setNeedsUpdateOfSupportedInterfaceOrientations()`。
        NotificationCenter.default.post(name: .readerOrientationLockChanged, object: nil)
    }
}

public extension Notification.Name {
    /// 阅读器方向锁定状态变化（UI 层据此调用 `setNeedsUpdateOfSupportedInterfaceOrientations`）。
    static let readerOrientationLockChanged = Notification.Name("InkSight.readerOrientationLockChanged")
}
