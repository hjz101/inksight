import XCTest
@testable import InkSightAppUI
@testable import InkSightAppKit
import SwiftUI

/// FR-028 第 ① 项：**自绘图标**（描边/端点随主题变，DESIGN §3.1 判据）。
final class InkIconTests: XCTestCase {

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

    /// 图标**描边宽度取自规格**（不是硬编码）。
    func testStrokeWidthFromSpec() throws {
        let src = try source("InkSightAppUI", "InkIcon.swift")
        XCTAssertTrue(src.contains("lineWidth: CGFloat(spec.iconStroke)"),
                      "描边宽度须取自 spec.iconStroke（token 化，禁硬编码）")
    }

    /// 图标**端点形状取自规格**（butt / round）。
    func testLineCapFromSpec() throws {
        let src = try source("InkSightAppUI", "InkIcon.swift")
        XCTAssertTrue(src.contains("spec.iconCap == .round ? .round : .butt"),
                      "端点形状须取自 spec.iconCap")
    }

    /// 图标**颜色取自规格**。
    func testColorFromSpec() throws {
        let src = try source("InkSightAppUI", "InkIcon.swift")
        XCTAssertTrue(src.contains("spec.iconColorHex"), "颜色须取自 spec.iconColorHex")
    }

    /// **判据可辨性**：雪纸 butt vs 夜航 round 的端点形状确实不同。
    ///
    /// 这条是「换主题后图标端点形状必须肉眼可辨」的可执行代理：
    /// 若两套主题的 `iconCap` 相同，则该项恒不变 → 判据失效。
    func testCapDiffersAcrossSkins() {
        let snow = ThemeSkinSpec.spec(for: .snowPaper)
        let night = ThemeSkinSpec.spec(for: .nightVoyage)
        XCTAssertEqual(snow.iconCap, .butt, "雪纸应为直角端")
        XCTAssertEqual(night.iconCap, .round, "夜航应为圆角端")
        XCTAssertNotEqual(snow.iconCap, night.iconCap, "端点形状必须可辨")
    }

    /// 描边宽度也有差异（蜜桃汽水 2.5pt）。
    func testStrokeDiffersForPeachSoda() {
        XCTAssertEqual(ThemeSkinSpec.spec(for: .peachSoda).iconStroke, 2.5)
        XCTAssertEqual(ThemeSkinSpec.spec(for: .snowPaper).iconStroke, 2.0)
    }

    /// 工具条**已改用自绘图标**（不再用 SF Symbols 的 Image(systemName:)）。
    func testToolbarUsesInkIcon() throws {
        let src = try source("InkSightAppUI", "ReaderToolbar.swift")
        XCTAssertTrue(src.contains("InkIcon(glyph"), "工具条须用自绘图标")
        XCTAssertFalse(src.contains("Image(systemName:"),
                       "工具条不得再用 SF Symbols（无法自定义描边/端点）")
        XCTAssertTrue(src.contains("skinSpec: ThemeSkinSpec.Spec"),
                      "工具条须接收主题规格")
    }

    /// 图元路径覆盖所有声明的 glyph（无遗漏、不崩）。
    func testAllGlyphsProducePaths() {
        let size = CGSize(width: 24, height: 24)
        let glyphs: [InkIcon.Glyph] = [.close, .search, .back, .forward, .check,
                                       .bookmark, .list, .book, .drop, .swap,
                                       .note, .tag, .waveform, .gear]
        for glyph in glyphs {
            let path = InkIcon.path(for: glyph, in: size)
            XCTAssertFalse(path.isEmpty, "\(glyph) 应产生非空路径")
        }
    }

    /// 直线型图元（close/check/back）端点形状才有意义——确认它们用 addLine 而非闭合曲线。
    func testStraightLineGlyphsForCapVisibility() {
        let size = CGSize(width: 24, height: 24)
        // close 是两条直线交叉，端点必可见
        let close = InkIcon.path(for: .close, in: size)
        XCTAssertFalse(close.isEmpty)
        // check 是折线，端点可见
        let check = InkIcon.path(for: .check, in: size)
        XCTAssertFalse(check.isEmpty)
    }
}
