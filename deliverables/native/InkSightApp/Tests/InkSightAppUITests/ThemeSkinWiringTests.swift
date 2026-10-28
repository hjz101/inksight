import XCTest
@testable import InkSightAppUI
import Foundation

/// FR-028 皮肤包的 **UI 接线**契约：四项必须真的联动，不是只有数据。
final class ThemeSkinWiringTests: XCTestCase {

    private func source(_ name: String) throws -> String {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/InkSightAppUI")
        let raw = try String(contentsOf: base.appendingPathComponent(name), encoding: .utf8)
        return raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return !t.hasPrefix("//") && !t.hasPrefix("///") && !t.hasPrefix("*")
            }.joined(separator: "\n")
    }

    /// 设置页有三套皮肤可选（强调色圆点 ＋ 名称）。
    func testSkinPickerInSettings() throws {
        let src = try source("PlaceholderScreens.swift")
        XCTAssertTrue(src.contains("ThemeSkinSpec.Skin.allCases"), "须遍历三套皮肤")
        XCTAssertTrue(src.contains("主题皮肤"), "须有主题皮肤设置段")
        XCTAssertTrue(src.contains("accentHex"), "选皮肤应展示强调色（第 ② 项）")
    }

    /// **第 ③ 项玻璃 tint 真的接线**：工具条接收 themeTint。
    func testGlassTintWiredToToolbar() throws {
        let toolbar = try source("ReaderToolbar.swift")
        XCTAssertTrue(toolbar.contains("themeTint"), "工具条须接收主题 tint")
        XCTAssertTrue(toolbar.contains("themeTint: themeTint"), "须透传给 GlassSurface")

        let reader = try source("ReaderSurface.swift")
        XCTAssertTrue(reader.contains("skinSpec.glassTintHex"), "阅读器须传主题 tint 色")
        XCTAssertTrue(reader.contains("skinSpec.glassTintOpacity"), "须传主题 tint 透明度")
    }

    /// GlassSurface 支持主题 tint 覆盖（否则第 ③ 项无法联动）。
    func testGlassSurfaceSupportsThemeTint() throws {
        let src = try source("GlassSurface.swift")
        XCTAssertTrue(src.contains("var themeTint"), "GlassSurface 须有 themeTint 参数")
        XCTAssertTrue(src.contains("themeTint: (hex: String, opacity: Double)?"),
                      "init 须接受 themeTint")
        // 主题 tint 优先于档位默认
        XCTAssertTrue(src.contains("if let themeTint"), "主题 tint 应优先于档位默认")
    }

    /// hex 解析器**单一来源**（避免两套解析产生色差 → 观感上"某项没变"）。
    func testSingleHexParser() throws {
        let src = try source("ColorHex.swift")
        XCTAssertTrue(src.contains("init(hexString: String)"), "须有统一 hex 解析")
        // 其他 UI 文件不得各自实现 hex 解析
        for file in ["ReaderSurface.swift", "PlaceholderScreens.swift"] {
            let s = try source(file)
            XCTAssertFalse(s.contains("init(hexString"), "\(file) 不得重复实现 hex 解析")
        }
    }
}
