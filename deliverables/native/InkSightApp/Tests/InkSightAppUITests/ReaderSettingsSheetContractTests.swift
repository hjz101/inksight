import XCTest
@testable import InkSightAppUI
import Foundation

/// FR-014 自绘浮层**四条可用性**契约测试（P0 逐条）。
final class ReaderSettingsSheetContractTests: XCTestCase {

    private func sheetSource() throws -> String {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/InkSightAppUI")
        let raw = try String(contentsOf: base.appendingPathComponent("ReaderSettingsSheet.swift"),
                             encoding: .utf8)
        // 剥离注释（注释里会提到这四条，属留痕不是实现）
        return raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return !t.hasPrefix("//") && !t.hasPrefix("///") && !t.hasPrefix("*")
            }
            .joined(separator: "\n")
    }

    /// ① **44pt 关闭按钮**（触控最小尺寸）。
    func testCloseButtonIs44pt() throws {
        let src = try sheetSource()
        XCTAssertTrue(src.contains("width: 44, height: 44")
                      || src.contains("frame(width: 44, height: 44)"),
                      "关闭按钮必须是 44×44pt 触控目标")
    }

    /// ② **`accessibilityAction(.escape)`**（无障碍关闭动作）。
    func testEscapeAccessibilityAction() throws {
        let src = try sheetSource()
        XCTAssertTrue(src.contains("accessibilityAction(.escape)"),
                      "必须提供 .escape 无障碍关闭动作")
    }

    /// ③ **36×4pt 把手**。
    func testHandleIs36x4() throws {
        let src = try sheetSource()
        XCTAssertTrue(src.contains("width: 36, height: 4"),
                      "把手必须是 36×4pt")
    }

    /// ④ **scrim 点击关闭**。
    func testScrimTapCloses() throws {
        let src = try sheetSource()
        XCTAssertTrue(src.contains("onTapGesture"),
                      "scrim 必须可点击关闭")
        XCTAssertTrue(src.contains("Color.black.opacity"), "须有 scrim 遮罩层")
    }

    /// 四种关闭方式**共用同一关闭入口**（`onClose`），不各写一套。
    func testSingleCloseEntryPoint() throws {
        let src = try sheetSource()
        let closeCalls = src.components(separatedBy: "onClose()").count - 1
        XCTAssertGreaterThanOrEqual(closeCalls, 3,
                                    "scrim/按钮/escape 至少三处调用同一 onClose")
    }

    /// 浮层走 L3 玻璃（D-28 白名单「浮层与工具栏」）。
    func testUsesL3Glass() throws {
        let src = try sheetSource()
        XCTAssertTrue(src.contains("GlassSurface(strength: .l3"),
                      "阅读设置浮层应为 L3 玻璃（白名单成员）")
    }

    /// 浮层支持 FR-014 四态（presentation 透传）。
    func testSupportsPresentationState() throws {
        let src = try sheetSource()
        XCTAssertTrue(src.contains("presentation: GlassPresentationState")
                      || src.contains("var presentation"),
                      "浮层须支持四态收起")
    }
}
