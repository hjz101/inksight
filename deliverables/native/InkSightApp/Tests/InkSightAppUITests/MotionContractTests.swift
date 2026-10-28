import XCTest
@testable import InkSightAppUI
import InkSightAppKit
import InkSightCore
import SwiftUI
import Foundation

/// 开发包 #9／#10 契约测试（UI 层）：13 个动效的**实现齐备性** ＋ **材质插值守卫**
/// ＋ **触发纪律**（只经 `MotionCoordinator.perform`）＋ **0 玻璃**。
final class MotionContractTests: XCTestCase {

    // MARK: - 13 个实现齐备

    /// 13 个动效**一个都不能少、也不能多**：每个 ID 一个实现视图。
    func testEveryMotionIDHasExactlyOneEffectImplementation() throws {
        let src = stripComments(try String(contentsOf: sourceURL("MotionEffects.swift"), encoding: .utf8))
        let expected = [
            "T1BookOpenEffect", "T2VersionSwapEffect", "T3ThemeWipeEffect",
            "T4RestoreSettleEffect", "T5SwitchRippleEffect", "T6InkGrowEffect",
            "EGG1CoverLiquidEffect", "EGG2PinchSpineEffect", "EGG3PaperPullEffect",
            "EGG4DogEarEffect", "EGG5ShakePanelEffect",
            "UIT1ChromeToggleEffect", "UIT2EdgeBackEffect",
        ]
        XCTAssertEqual(expected.count, 13, "必须是 13 个")
        for name in expected {
            XCTAssertTrue(src.contains("struct \(name)"), "缺少 \(name) 的实现")
        }
        // 运行时面板须承载全部 13 个（一个不多一个不少）
        let screen = stripComments(try String(contentsOf: sourceURL("MotionRuntimeScreen.swift"), encoding: .utf8))
        for name in expected {
            XCTAssertTrue(screen.contains("\(name)()"), "运行时面板缺少 \(name) 的触发点")
        }
    }

    // MARK: - 触发纪律（NFR-10 单一真相）

    /// 触发点**只调 `MotionCoordinator.perform`**，不得自己读设置文件。
    func testTriggersGoThroughMotionCoordinatorPerformOnly() throws {
        for name in ["MotionEffects.swift", "MotionRuntimeScreen.swift"] {
            let src = stripComments(try String(contentsOf: sourceURL(name), encoding: .utf8))
            XCTAssertFalse(src.contains("MotionSettingsStore("),
                           "\(name) 触发点不得直接读设置文件（NFR-10 单一真相）")
            XCTAssertFalse(src.contains("MotionSettings.default"),
                           "\(name) 触发点不得直接读设置模型")
            XCTAssertFalse(src.contains("perID["),
                           "\(name) 触发点不得直接读 perID 开关")
        }
        let effects = stripComments(try String(contentsOf: sourceURL("MotionEffects.swift"), encoding: .utf8))
        let performCount = effects.components(separatedBy: "MotionCoordinator.shared.perform(").count - 1
        XCTAssertGreaterThanOrEqual(performCount, 13,
                                     "13 个动效的触发必须各经 MotionCoordinator.perform")
    }

    // MARK: - 材质插值守卫（FR-030 硬纪律）

    /// 动效路径**不得插值材质参数**（tint/blur/refraction/Material）——
    /// 材质一变即触发 backdrop 全屏重算（四层叠加，成本远高于单层），**T3 最易犯**。
    ///
    /// 判据用**源码扫描**（去注释后）：命中任一材质插值记号即判不通过。
    func testMotionEffectsDoNotInterpolateMaterialParameters() throws {
        let forbidden = ["refraction", ".blur(", "Material", ".glassEffect", "tint("]
        for name in ["MotionEffects.swift", "MotionRuntimeScreen.swift"] {
            let src = stripComments(try String(contentsOf: sourceURL(name), encoding: .utf8))
            for token in forbidden {
                XCTAssertFalse(src.contains(token),
                               "\(name) 不得出现材质插值记号「\(token)」（动效期间只允许插值 opacity 与 transform）")
            }
        }
    }

    // MARK: - 0 玻璃

    /// 0 玻璃：新增动效文件不得引用 `GlassSurface` / `GlassStrength` / `.glassEffect`。
    func testMotionEffectFilesHaveNoGlassReference() throws {
        for name in ["MotionEffects.swift", "MotionRuntimeScreen.swift"] {
            let src = stripComments(try String(contentsOf: sourceURL(name), encoding: .utf8))
            XCTAssertFalse(src.contains("GlassSurface"), "\(name) 不得引用 GlassSurface")
            XCTAssertFalse(src.contains("GlassStrength"), "\(name) 不得引用 GlassStrength")
            XCTAssertFalse(src.contains("glassEffect"), "\(name) 不得调用 .glassEffect")
        }
    }

    // MARK: - 构造不崩

    /// 13 个动效视图 ＋ 运行时面板均可正常构造（不崩溃）。
    @MainActor
    func testAllEffectViewsConstructWithoutCrash() {
        _ = T1BookOpenEffect()
        _ = T2VersionSwapEffect()
        _ = T3ThemeWipeEffect()
        _ = T4RestoreSettleEffect()
        _ = T5SwitchRippleEffect()
        _ = T6InkGrowEffect()
        _ = EGG1CoverLiquidEffect()
        _ = EGG2PinchSpineEffect()
        _ = EGG3PaperPullEffect()
        _ = EGG4DogEarEffect()
        _ = EGG5ShakePanelEffect()
        _ = UIT1ChromeToggleEffect()
        _ = UIT2EdgeBackEffect()
        _ = MotionRuntimeScreen()
    }

    // MARK: - 源码路径 / 注释剥离（测试工具）

    private func sourceURL(_ name: String) -> URL {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/InkSightAppUITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // InkSightApp
        return base.appendingPathComponent("Sources/InkSightAppUI").appendingPathComponent(name)
    }

    private func stripComments(_ source: String) -> String {
        var out = ""
        var i = source.startIndex
        let s = source
        while i < s.endIndex {
            if s[i...].hasPrefix("/*") {
                if let end = s[i...].range(of: "*/") { i = end.upperBound; continue }
                break
            }
            if s[i...].hasPrefix("//") {
                if let nl = s[i...].firstIndex(of: "\n") { i = nl; continue }
                break
            }
            out.append(s[i])
            i = s.index(after: i)
        }
        return out
    }
}
