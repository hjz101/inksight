import XCTest
@testable import InkSightAppUI
@testable import InkSightAppKit
import Foundation

/// FR-028 **四项真正联动**的补强测试（D-95：② 全局强调色 / ④ 转场配色 / radiusShift）。
final class ThemeSkinLayersTests: XCTestCase {

    private func source(_ module: String, _ name: String) throws -> String {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/\(module)")
        let raw = try String(contentsOf: base.appendingPathComponent(name), encoding: .utf8)
        return raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return !t.hasPrefix("//") && !t.hasPrefix("///") && !t.hasPrefix("*")
            }.joined(separator: "\n")
    }

    /// **第 ② 项**：全局 `.tint()` 注入皮肤强调色（不只是皮肤选择器圆点）。
    func testGlobalTintInjected() throws {
        let src = try source("InkSightAppMain", "InkSightRootApp.swift")
        XCTAssertTrue(src.contains(".tint(Color(hexString: skinSpec.accentHex))"),
                      "根视图须注入全局强调色（FR-028 第 ② 项）")
    }

    /// **第 ④ 项**：转场配色接入（换皮肤即播色带漫延）。
    func testTransitionColorWired() throws {
        let root = try source("InkSightAppMain", "InkSightRootApp.swift")
        XCTAssertTrue(root.contains("ThemeWipeOverlay"), "根视图须叠转场层")

        let settings = try source("InkSightAppUI", "PlaceholderScreens.swift")
        XCTAssertTrue(settings.contains("wipe.wipe(to:"), "换皮肤须触发转场")
    }

    /// 转场规格：**420ms ＋ 径向裁剪 ＋ 纯色渐变（非玻璃）**。
    func testWipeSpecCompliance() throws {
        let src = try source("InkSightAppUI", "ThemeWipeOverlay.swift")
        XCTAssertTrue(src.contains("0.42"), "时长须为 420ms（DESIGN §4.1 T3）")
        XCTAssertTrue(src.contains("clipShape"), "须径向裁剪（禁写渐变染色）")
        XCTAssertTrue(src.contains("LinearGradient"), "色带须为纯色渐变")
        // 色带层**不得**经 GlassSurface（玻璃层破 NFR-06）
        XCTAssertFalse(src.contains("GlassSurface"), "转场色带不得使用玻璃")
    }

    /// **radiusShift**（蜜桃汽水 +4）应用到实际圆角，不是只有数据。
    func testRadiusShiftApplied() throws {
        let toolbar = try source("InkSightAppUI", "ReaderToolbar.swift")
        XCTAssertTrue(toolbar.contains("CGFloat(radiusShift)"),
                      "圆角须由 radiusShift 计算（token 化，禁硬编码）")
        let reader = try source("InkSightAppUI", "ReaderSurface.swift")
        XCTAssertTrue(reader.contains("skinSpec.radiusShift"), "阅读器须传 radiusShift")
    }

    /// 转场 layer 不得插值材质参数（只动裁剪半径/opacity）。
    func testWipeDoesNotAnimateMaterial() throws {
        let src = try source("InkSightAppUI", "ThemeWipeOverlay.swift")
        // 不得对 tint/blur/refraction 做动画
        XCTAssertFalse(src.contains("animate"),
                       "转场层不得插值材质参数（只允许 opacity/transform/裁剪）")
    }

    /// 三套皮肤的转场配色两两不同（第 ④ 项四项联动的一部分）。
    func testTransitionColorsDifferPerSkin() {
        let specs = ThemeSkinSpec.Skin.allCases.map { ThemeSkinSpec.spec(for: $0) }
        let froms = Set(specs.map(\.transitionFromHex))
        XCTAssertEqual(froms.count, 3, "三套皮肤的转场起色应各不相同")
    }
}
