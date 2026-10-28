import XCTest
@testable import InkSightAppKit

/// EGG4 关闭态语义：`dropTrigger` 必须**连触发一起短路**（书签不写），
/// 功能由工具条「书签」等价路径承担。
final class Egg4TriggerPolicyTests: XCTestCase {

    /// EGG4 的触发策略必须是 `dropTrigger`，且**有非手势等价路径**。
    ///
    /// DESIGN §4.1：彩蛋可注销的前提是存在非手势等价路径——缺一则必须降为 `.keepTrigger`。
    func testEgg4IsDropTriggerWithEquivalentPath() {
        let spec = MotionRegistry.spec(for: .egg4DogEar)
        guard case .dropTrigger(let equivalentPath) = spec.triggerPolicy else {
            return XCTFail("EGG4 应为 dropTrigger（彩蛋可注销）")
        }
        XCTAssertNotNil(equivalentPath, "dropTrigger 必须声明非手势等价路径")
        XCTAssertFalse(equivalentPath?.isEmpty ?? true, "等价路径不能是空串")
    }

    /// **关闭态下 `perform` 不执行闭包**（dropTrigger 语义）。
    ///
    /// 这条守的是：把书签写入放在 perform 闭包内 → 关闭彩蛋后书签不会被彩蛋写，
    /// 只能走工具条「书签」入口。
    @MainActor
    func testDisabledEgg4DoesNotRunClosure() {
        let coordinator = MotionCoordinator.shared
        let original = MotionSettingsStore().load()
        defer { coordinator.apply(original) }

        // 关闭 EGG4（单关）
        var settings = MotionSettings()
        settings.globalEnabled = true
        settings.perID[MotionID.egg4DogEar.rawValue] = false
        coordinator.apply(settings)
        XCTAssertFalse(coordinator.isEnabled(.egg4DogEar))

        var ran = false
        coordinator.perform(.egg4DogEar) { ran = true }
        XCTAssertFalse(ran, "EGG4 关闭态不得执行触发闭包（dropTrigger）")
    }

    /// 开启态下闭包照常执行。
    @MainActor
    func testEnabledEgg4RunsClosure() {
        let coordinator = MotionCoordinator.shared
        let original = MotionSettingsStore().load()
        defer { coordinator.apply(original) }

        var settings = MotionSettings()
        settings.globalEnabled = true
        settings.perID[MotionID.egg4DogEar.rawValue] = true
        coordinator.apply(settings)

        var ran = false
        coordinator.perform(.egg4DogEar) { ran = true }
        XCTAssertTrue(ran, "EGG4 开启态应执行触发闭包")
    }
}
