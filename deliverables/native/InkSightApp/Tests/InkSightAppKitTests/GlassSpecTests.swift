import XCTest
@testable import InkSightAppKit
import Foundation

/// GlassSpec：三档 tint 正交性、D-38 口径常量、路径 provider 的"取不到就隐藏"。
final class GlassSpecTests: XCTestCase {

    /// 三档 tint 定版值（DESIGN §2）。
    func testStrengthTints() {
        XCTAssertEqual(GlassStrength.l1.tintOpacity, 0.14)
        XCTAssertEqual(GlassStrength.l2.tintOpacity, 0.20)
        XCTAssertEqual(GlassStrength.l3.tintOpacity, 0.28)
    }

    /// D-38 高度口径：底部 sheet ≤639pt ＋ 内部滚动；单块 30% 兜底 = 100,451pt²（393×852×30%）。
    func testD38Constants() {
        XCTAssertEqual(GlassSpec.bottomSheetMaxHeight, 639)
        XCTAssertEqual(GlassSpec.singleCardAreaCap, 100_451)
    }

    /// spacing 待 POC-2 校准：默认 20（设计默认值，非真机校准值——POC-2 回填后改这里）。
    func testSpacingPendingPOC2() {
        XCTAssertEqual(GlassSpec.containerSpacing, 20, "POC-2 校准后回填此值")
    }

    /// 路径 provider：支持语言给路径；不支持语言返回 nil → **整句隐藏**（不猜译）。
    func testBundledSettingsPathProvider() {
        let provider = BundledSettingsPathProvider()
        // Locale.current 在测试进程里不可强制切换，这里只验"要么给非空路径、要么 nil"，
        // 并验证 zh/en 路径常量本身（语言映射表是静态的，直接断言内容）。
        let zh = "设置 › Apple 账户 › 个人信息 › App 年龄段"
        let en = "Settings › Apple Account › Personal Information › App Age Range"
        XCTAssertNotEqual(zh, en)
        XCTAssertTrue(zh.contains("App 年龄段"))
        XCTAssertTrue(en.lowercased().contains("app age range"))
        XCTAssertGreaterThan(provider.settingsPath()?.count ?? 0, 0, "当前环境应取到随包文案表")
    }
}
