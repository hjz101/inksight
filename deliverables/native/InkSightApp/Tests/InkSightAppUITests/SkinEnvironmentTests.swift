import XCTest
@testable import InkSightAppUI
@testable import InkSightAppKit
import SwiftUI

/// FR-028 全站皮肤联动契约测试。
///
/// 判据来自 DESIGN §3.1：「任一项不随主题动即判未完成」。
/// D-97 做图标替换时 31 处写死雪纸规格 → 只有工具条跟随主题，属"未完成"。
final class SkinEnvironmentTests: XCTestCase {

    private func allUISources() throws -> [(String, String)] {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/InkSightAppUI")
        let files = try FileManager.default.contentsOfDirectory(atPath: base.path)
            .filter { $0.hasSuffix(".swift") }
        return try files.map { name in
            let raw = try String(contentsOf: base.appendingPathComponent(name), encoding: .utf8)
            let stripped = raw.split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
                .filter {
                    let t = $0.trimmingCharacters(in: .whitespaces)
                    return !t.hasPrefix("//") && !t.hasPrefix("///") && !t.hasPrefix("*")
                }.joined(separator: "\n")
            return (name, stripped)
        }
    }

    /// **零硬编码**：UI 层不得再出现 `spec(for: .snowPaper)`。
    ///
    /// 只允许两处例外：`SkinEnvironment.swift`（默认值定义）与 `ReaderToolbar`（显式传参演示）。
    func testNoHardcodedSkinInUI() throws {
        for (name, src) in try allUISources() {
            if name == "SkinEnvironment.swift" || name == "ReaderToolbar.swift" { continue }
            XCTAssertFalse(src.contains("spec(for: .snowPaper)"),
                           "\(name) 仍硬编码雪纸规格（应改用 ThemedInkIcon / 环境注入）")
        }
    }

    /// 根视图注入了皮肤环境值。
    func testRootInjectsSkin() throws {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/InkSightAppMain")
        let src = try String(contentsOf: base.appendingPathComponent("InkSightRootApp.swift"),
                            encoding: .utf8)
        XCTAssertTrue(src.contains(".themeSkin(skinSpec)"),
                      "根视图须注入皮肤环境值")
    }

    /// 图标使用 `ThemedInkIcon`（从环境读规格），而非硬编码。
    func testIconsUseThemedVariant() throws {
        var themed = 0
        for (_, src) in try allUISources() {
            themed += src.components(separatedBy: "ThemedInkIcon(").count - 1
        }
        XCTAssertGreaterThanOrEqual(themed, 25,
                                    "多数图标应使用 ThemedInkIcon（实际 \(themed) 处）")
    }

    /// 环境键有默认值（未被注入时也能渲染，不崩）。
    func testEnvironmentHasDefault() {
        let defaultValue = ThemeSkinSpec.spec(for: .snowPaper)
        XCTAssertEqual(defaultValue.accentHex, "#B8452F", "默认应为雪纸")
    }
}
