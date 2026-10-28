import XCTest
@testable import InkSightAppKit
import Foundation

/// 开发包 #7 契约测试：FR-030 per-ID 独立开关。
///
/// 覆盖：per-ID 隔离、全局总关优先、keepTrigger 保功能 / dropTrigger 短路、
/// `animation(for:)` 对单关 ID 返回 nil、可关集合恰 11 个且 T4／T5 不在内、中文名禁用词自检。
final class MotionPerIDTests: XCTestCase {

    // MARK: - per-ID 隔离

    /// 单关某 ID **只影响该 ID**，其余 ID 一律不受影响（逐 ID 隔离）。
    @MainActor
    func testPerIDDisableAffectsOnlyThatID() {
        let coordinator = MotionCoordinator()
        XCTAssertTrue(coordinator.isEnabled(.t1BookOpen))

        coordinator.setEnabled(false, for: .t1BookOpen)

        XCTAssertFalse(coordinator.isEnabled(.t1BookOpen), "被单关的 ID 应失效")
        XCTAssertTrue(coordinator.isIndividuallyDisabled(.t1BookOpen))
        XCTAssertNil(coordinator.animation(for: .t1BookOpen), "被单关的 ID 应走不播动画路径")

        for id in MotionID.allCases where id != .t1BookOpen {
            XCTAssertTrue(coordinator.isEnabled(id), "\(id) 不应受 T1 单关影响")
            XCTAssertNotNil(coordinator.animation(for: id), "\(id) 动画不应受 T1 单关影响")
        }
    }

    /// 单关 EGG1（dropTrigger）不得牵连其他彩蛋。
    @MainActor
    func testPerIDDropTriggerDoesNotAffectOtherEggs() {
        let coordinator = MotionCoordinator()
        coordinator.setEnabled(false, for: .egg1CoverLiquid)
        XCTAssertFalse(coordinator.isEnabled(.egg1CoverLiquid))
        for id in [MotionID.egg2PinchSpine, .egg3PaperPull, .egg4DogEar, .egg5ShakePanel] {
            XCTAssertTrue(coordinator.isEnabled(id), "\(id) 不应受 EGG1 单关影响")
        }
    }

    // MARK: - 全局总关优先级最高

    /// 总关时即使某 ID 单独开着也不播（单 ID 开关不能绕过总关）。
    @MainActor
    func testGlobalOffOverridesPerID() {
        let coordinator = MotionCoordinator()
        coordinator.setEnabled(true, for: .t1BookOpen)
        coordinator.setMotionEnabled(false)
        XCTAssertFalse(coordinator.isEnabled(.t1BookOpen), "总关优先级最高")
        XCTAssertNil(coordinator.animation(for: .t1BookOpen))

        // 反向构造：总关 + 该 ID 单独「开」→ 仍不播
        let injected = MotionCoordinator()
        injected.apply(MotionSettings(globalEnabled: false,
                                      perID: [MotionID.t1BookOpen.rawValue: true]))
        XCTAssertFalse(injected.isEnabled(.t1BookOpen))
        XCTAssertNil(injected.animation(for: .t1BookOpen))
    }

    /// 总关时**所有** ID 都不播（不限单关与否）。
    @MainActor
    func testGlobalOffDisablesEveryID() {
        let coordinator = MotionCoordinator()
        coordinator.setMotionEnabled(false)
        for id in MotionID.allCases {
            XCTAssertFalse(coordinator.isEnabled(id), "\(id) 总关后必须失效")
            XCTAssertNil(coordinator.animation(for: id), "\(id) 总关后必须走不播动画路径")
        }
    }

    // MARK: - 关态触发规则（逐 ID）

    /// 单关 keepTrigger 的 ID → **状态变更仍生效**（只减掉动画，不减掉能力）。
    /// 单关 dropTrigger 的 ID → **连触发一起短路**。
    @MainActor
    func testPerIDKeepTriggerPreservesFunctionAndDropTriggerShortCircuits() {
        let coordinator = MotionCoordinator()
        coordinator.setEnabled(false, for: .t2VersionSwap)   // keepTrigger
        var applied = false
        coordinator.perform(.t2VersionSwap) { applied = true }
        XCTAssertTrue(applied, "单关 keepTrigger 的 ID：功能不能减掉（反馈必须留，动画不必播）")

        let other = MotionCoordinator()
        other.setEnabled(false, for: .egg5ShakePanel)        // dropTrigger
        var fired = false
        other.perform(.egg5ShakePanel) { fired = true }
        XCTAssertFalse(fired, "单关 dropTrigger 的 ID：连触发一起短路（摇动无响应）")

        // 对照：其余 ID 不受该单关影响（dropTrigger 的 EGG4 仍应触发）
        var firedOther = false
        other.perform(.egg4DogEar) { firedOther = true }
        XCTAssertTrue(firedOther, "其他 ID 不应受 EGG5 单关影响")
    }

    // MARK: - 可关集合与分组（FR-030 原文②）

    /// 可关集合**恰为 11 个**；T4／T5 不在其中；分组规模为 转场 4／彩蛋 5／手势 2。
    func testClosableSetIsExactlyElevenAndGroupsAreFourFiveTwo() {
        let expected: Set<MotionID> = [
            .t1BookOpen, .t2VersionSwap, .t3ThemeWipe, .t6InkGrow,
            .egg1CoverLiquid, .egg2PinchSpine, .egg3PaperPull, .egg4DogEar, .egg5ShakePanel,
            .uit1ChromeToggle, .uit2EdgeBack,
        ]
        XCTAssertEqual(MotionRegistry.perIDSwitchableIDs.count, 11, "可关集合必须恰好 11 个")
        XCTAssertEqual(Set(MotionRegistry.perIDSwitchableIDs), expected, "可关集合成员不符")

        XCTAssertFalse(MotionRegistry.perIDSwitchableIDs.contains(.t4RestoreSettle), "T4 无单独开关")
        XCTAssertFalse(MotionRegistry.perIDSwitchableIDs.contains(.t5SwitchRipple), "T5 无单独开关")

        XCTAssertEqual(MotionRegistry.ids(inGroup: .transition).count, 4, "转场组应 4 个")
        XCTAssertEqual(MotionRegistry.ids(inGroup: .easterEgg).count, 5, "彩蛋组应 5 个")
        XCTAssertEqual(MotionRegistry.ids(inGroup: .gesture).count, 2, "手势组应 2 个")

        // 三组合计 = 11，且各组 ID 均属可关集合
        let grouped = MotionGroup.allCases.flatMap { MotionRegistry.ids(inGroup: $0) }
        XCTAssertEqual(grouped.count, 11)
        XCTAssertEqual(Set(grouped), expected)
        // T4／T5 不得出现在任何分组结果里（UI 上结构上不生成这两行）
        XCTAssertFalse(grouped.contains(.t4RestoreSettle))
        XCTAssertFalse(grouped.contains(.t5SwitchRipple))
    }

    /// 13 个 ID 全部有分组归属（穷举保证——新增 case 编译期即失败）。
    func testEveryMotionIDHasGroupAssignment() {
        for id in MotionID.allCases {
            _ = MotionRegistry.group(for: id)
        }
        XCTAssertEqual(MotionGroup.allCases.count, 3)
        XCTAssertEqual(MotionGroup.allCases.map(\.chineseName), ["转场", "彩蛋", "手势"])
    }

    // MARK: - 注入驱动（不依赖磁盘）

    /// `apply(_:)` 可在不依赖磁盘的情况下驱动任意开关组合；`currentSettings()` 快照形状正确。
    @MainActor
    func testApplySettingsDrivesCombinationsWithoutDisk() {
        let coordinator = MotionCoordinator()
        var perID: [String: Bool] = [:]
        for id in MotionRegistry.perIDSwitchableIDs { perID[id.rawValue] = true }
        perID[MotionID.egg1CoverLiquid.rawValue] = false

        coordinator.apply(MotionSettings(globalEnabled: true, perID: perID))

        XCTAssertTrue(coordinator.isEnabled(.t1BookOpen))
        XCTAssertFalse(coordinator.isEnabled(.egg1CoverLiquid))
        XCTAssertNil(coordinator.animation(for: .egg1CoverLiquid))

        let snapshot = coordinator.currentSettings()
        XCTAssertTrue(snapshot.globalEnabled)
        XCTAssertEqual(snapshot.perID.count, 11)
        XCTAssertFalse(snapshot.isEnabled(.egg1CoverLiquid))
        XCTAssertTrue(snapshot.isEnabled(.t1BookOpen))
    }

    /// `setEnabled(_:for:)` 与 `apply(_:)` 两条入口状态一致（无隐藏的第二真相）。
    @MainActor
    func testSetEnabledAndApplyAgree() {
        let viaSetter = MotionCoordinator()
        viaSetter.setEnabled(false, for: .uit2EdgeBack)

        let viaApply = MotionCoordinator()
        viaApply.apply(MotionSettings(globalEnabled: true,
                                      perID: [MotionID.uit2EdgeBack.rawValue: false]))

        XCTAssertEqual(viaSetter.currentSettings(), viaApply.currentSettings())
        XCTAssertFalse(viaSetter.isEnabled(.uit2EdgeBack))
        XCTAssertFalse(viaApply.isEnabled(.uit2EdgeBack))
    }

    // MARK: - 中文名禁用词自检（FR-030 明文）

    /// ID 中文名不得出现「书源／破解／解锁／全网／免费」。
    func testChineseNamesContainNoForbiddenWords() {
        let forbidden = ["书源", "破解", "解锁", "全网", "免费"]
        for spec in MotionRegistry.all {
            for word in forbidden {
                XCTAssertFalse(spec.chineseName.contains(word),
                               "\(spec.id) 的中文名「\(spec.chineseName)」含禁用词「\(word)」")
            }
        }
    }
}
