import XCTest
@testable import InkSightAppKit

/// FR-037 阅读器锁竖屏契约测试。
final class OrientationControllerTests: XCTestCase {

    /// 初始状态：未锁定（其他界面可旋转）。
    func testInitialStateUnlocked() {
        let c = OrientationController()
        XCTAssertFalse(c.isReaderPortraitLocked)
        XCTAssertEqual(c.allowedOrientationMask, OrientationController.allSupportedMask)
    }

    /// 锁定后仅竖屏；解锁后恢复。
    func testLockUnlock() {
        let c = OrientationController()
        c.lockReaderToPortrait()
        XCTAssertTrue(c.isReaderPortraitLocked)
        XCTAssertEqual(c.allowedOrientationMask, OrientationController.portraitMask)

        c.unlockAfterReader()
        XCTAssertFalse(c.isReaderPortraitLocked)
        XCTAssertEqual(c.allowedOrientationMask, OrientationController.allSupportedMask)
    }

    /// 掩码语义：portrait=2；all=portrait|left|right。
    func testMaskSemantics() {
        XCTAssertEqual(OrientationController.portraitMask, 2, "UIInterfaceOrientationMaskPortrait = 1<<1")
        XCTAssertEqual(OrientationController.allSupportedMask, 2 | 8 | 16,
                       "竖屏＋左右横屏")
        XCTAssertTrue((OrientationController.allSupportedMask & OrientationController.portraitMask) != 0,
                      "all 必须含竖屏")
    }

    /// 锁定状态变化时发通知（UI 层据此 setNeedsUpdateOfSupportedInterfaceOrientations）。
    func testLockChangePostsNotification() {
        let c = OrientationController()
        var notified = 0
        let token = NotificationCenter.default.addObserver(
            forName: .readerOrientationLockChanged, object: nil, queue: .main) { _ in
            notified += 1
        }
        c.lockReaderToPortrait()
        c.unlockAfterReader()
        c.lockReaderToPortrait()
        XCTAssertEqual(notified, 3, "每次状态变化都应通知（首次锁定、解锁、再锁定）")
        NotificationCenter.default.removeObserver(token)
    }

    /// 重复锁定同一状态不发通知（幂等）。
    func testNoNotificationWhenUnchanged() {
        let c = OrientationController()
        var notified = 0
        let token = NotificationCenter.default.addObserver(
            forName: .readerOrientationLockChanged, object: nil, queue: .main) { _ in
            notified += 1
        }
        c.lockReaderToPortrait()
        c.lockReaderToPortrait()   // 已锁定，不变
        XCTAssertEqual(notified, 1, "重复锁定同一状态不应重复通知")
        NotificationCenter.default.removeObserver(token)
    }
}
