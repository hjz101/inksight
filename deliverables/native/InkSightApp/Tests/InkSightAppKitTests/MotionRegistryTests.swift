import XCTest
@testable import InkSightAppKit
import Foundation

/// FR-030：MotionRegistry 穷举 13 case、可关性元数据、唯一动画入口。
final class MotionRegistryTests: XCTestCase {

    /// 穷举 13 case（T1–T6、EGG1–EGG5、UIT1–UIT2），ID 唯一。
    func testExhaustiveThirteenCases() {
        XCTAssertEqual(MotionID.allCases.count, 13)
        XCTAssertEqual(Set(MotionID.allCases.map(\.rawValue)).count, 13, "raw value 不得重复")
        XCTAssertEqual(MotionRegistry.all.count, 13, "Registry 必须登记全部 13 条（穷举 switch 保证）")
        XCTAssertEqual(Set(MotionRegistry.all.map(\.id)), Set(MotionID.allCases), "Registry 与 MotionID 必须一一对应")
    }

    /// 可关性：13 条全部 A 档可关（T4 直切回位、T5 0ms 静态成功态——反馈必须留，动画不必播）。
    func testAllClosable() {
        for spec in MotionRegistry.all {
            XCTAssertTrue(spec.closable, "\(spec.id) 应为可关")
        }
    }

    /// 关态触发规则（DESIGN §8 三分类）：功能性/装饰性反馈保留触发；纯彩蛋注销须有等价路径。
    func testTriggerPoliciesMatchDesignRuling() {
        // 功能性动效：触发必须保留
        for id in [MotionID.t1BookOpen, .t2VersionSwap, .t3ThemeWipe, .t4RestoreSettle,
                   .t5SwitchRipple, .t6InkGrow, .uit1ChromeToggle, .uit2EdgeBack] {
            guard case .keepTrigger = MotionRegistry.spec(for: id).triggerPolicy else {
                XCTFail("\(id) 应为 keepTrigger（功能不能关，只关动画）")
                continue
            }
        }
        // 纯彩蛋：逻辑注销；有功能出口的必须给出等价路径
        for (id, expectedPath) in [(MotionID.egg2PinchSpine, "书架视图切换条按钮"),
                                   (MotionID.egg4DogEar, "chrome 菜单加书签"),
                                   (MotionID.egg5ShakePanel, "chrome 菜单换一份文件")] {
            guard case .dropTrigger(let path) = MotionRegistry.spec(for: id).triggerPolicy else {
                XCTFail("\(id) 应为 dropTrigger"); continue
            }
            XCTAssertEqual(path, expectedPath, "\(id) 的等价路径不符")
        }
        // EGG1 纯装饰：注销且无功能损失（nil）
        guard case .dropTrigger(let egg1Path) = MotionRegistry.spec(for: .egg1CoverLiquid).triggerPolicy else {
            XCTFail("EGG1 应为 dropTrigger"); return
        }
        XCTAssertNil(egg1Path, "EGG1 纯装饰，不应伪造等价路径")
        // EGG3：装饰不创建，下拉刷新仍生效 → keepTrigger
        guard case .keepTrigger = MotionRegistry.spec(for: .egg3PaperPull).triggerPolicy else {
            XCTFail("EGG3 下拉刷新是功能，触发必须保留"); return
        }
    }

    /// EGG5：shake 注册与 3 次/分限流是同一条开关（designer 规范原文）——
    /// 注册随 dropTrigger 一并停跑，不得分别修改。
    @MainActor
    func testEgg5ShakeNeverFiresWhenMotionOff() {
        let coordinator = MotionCoordinator(isMotionEnabled: false)
        var fired = false
        XCTAssertNil(coordinator.animation(for: .egg5ShakePanel))
        coordinator.perform(.egg5ShakePanel) { fired = true }
        XCTAssertFalse(fired, "纯彩蛋在总关下连触发一起短路（摇动无响应、限流一并停跑）")
        // 对照：功能性动效在总关下仍执行状态变更（无动画）——功能不能关
        var applied = false
        coordinator.perform(.t2VersionSwap) { applied = true }
        XCTAssertTrue(applied, "总关只关动画，不关功能")
    }

    /// 全局总关＝不播动画路径（animation(for:) → nil），不是时长设 0。
    @MainActor
    func testGlobalOffYieldsNilAnimation() {
        let off = MotionCoordinator(isMotionEnabled: false)
        let on = MotionCoordinator(isMotionEnabled: true)
        for id in MotionID.allCases {
            XCTAssertNil(off.animation(for: id), "\(id) 总关后必须走不播动画路径")
            XCTAssertNotNil(on.animation(for: id), "\(id) 开启态应有动画")
        }
    }

    /// EGG1 同 ID 双表现（单 case + variant，不分裂枚举）。
    func testEgg1Variants() {
        XCTAssertEqual(MotionRegistry.egg1Variants(for: .egg1CoverLiquid).count, 2)
        XCTAssertTrue(MotionRegistry.egg1Variants(for: .t1BookOpen).isEmpty, "非 EGG1 不得返回 variant")
    }

    /// 契约抽查：中文语义名与英文 raw value 对齐 DESIGN §4.1（抽 T2/T5/UIT1 三个易漂移点）。
    func testSemanticNames() {
        XCTAssertEqual(MotionRegistry.spec(for: .t2VersionSwap).englishName, "versionSwap")
        XCTAssertEqual(MotionRegistry.spec(for: .t2VersionSwap).chineseName, "版本层翻片")
        XCTAssertEqual(MotionRegistry.spec(for: .t5SwitchRipple).chineseName, "切换涟漪")
        XCTAssertEqual(MotionRegistry.spec(for: .uit1ChromeToggle).englishName, "chromeToggle")
    }
}
