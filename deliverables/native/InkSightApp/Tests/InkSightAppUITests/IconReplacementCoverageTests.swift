import XCTest
@testable import InkSightAppUI
import Foundation

/// FR-028 第 ① 项**全量替换覆盖度**测试。
///
/// 纪律：`Image(systemName:)` 必须清零（本项目已全部改自绘）；
/// **系统 TabBar 的 `Label(_:systemImage:)` 是明确的例外**——图标由系统渲染，
/// 自定义描边/端点无法生效。例外必须**写成断言并注明原因**，不能静默放过。
final class IconReplacementCoverageTests: XCTestCase {

    private func uiSources() throws -> [(String, String)] {
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

    /// **`Image(systemName:)` 零残留**（除 InkIcon 自身的 Path 绘制外）。
    func testNoResidualSystemImages() throws {
        for (name, src) in try uiSources() {
            XCTAssertFalse(src.contains("Image(systemName:"),
                           "\(name) 仍使用 SF Symbols（无法自定义描边/端点）")
        }
    }

    /// TabBar 的 `Label(systemImage:)` 是**唯一例外**，且限定在根视图 5 个 tab。
    ///
    /// 原因：SwiftUI `TabView` 的 tabItem 由系统渲染，我方无法注入 `InkIcon`。
    /// 这条断言让例外**可见**——若将来第 6 个 tab 或别处出现 Label(systemImage:)，
    /// 测试会失败，避免"例外"悄悄扩散成"普遍"。
    func testTabBarIsTheOnlyLabelSymbolException() throws {
        var total = 0
        for (name, src) in try uiSources() {
            let count = src.components(separatedBy: "Label(").count - 1
            let withSymbol = src.components(separatedBy: "systemImage:").count - 1
            if withSymbol > 0 {
                XCTAssertEqual(name, "InkSightRootApp.swift",
                               "\(name) 不应使用 Label(systemImage:)，例外仅限 TabBar")
                total += withSymbol
            }
            _ = count
        }
        XCTAssertEqual(total, 5, "TabBar 恰 5 个 tab（发现/书架/墨迹/墨量/我）")
    }

    /// 自绘图标覆盖了项目实际用到的语义图元。
    func testGlyphCoverage() {
        // 替换表中用到的全部 glyph 都必须在 InkIcon.Glyph 里存在
        let used: [InkIcon.Glyph] = [.close, .search, .back, .forward, .check,
                                     .bookmark, .list, .book, .drop, .swap,
                                     .note, .tag, .waveform, .gear,
                                     .tray, .highlighter, .pin, .play, .pause]
        // 逐个能产生非空路径即证明存在且可用
        let size = CGSize(width: 24, height: 24)
        for glyph in used {
            XCTAssertFalse(InkIcon.path(for: glyph, in: size).isEmpty,
                           "\(glyph) 应有有效路径")
        }
    }
}
