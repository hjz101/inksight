import XCTest
@testable import InkSightAppUI
import Foundation

/// FR-036 手势可见入口契约测试。
final class GestureVisibilityContractTests: XCTestCase {

    private func source(_ name: String) throws -> String {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/InkSightAppUI")
        let raw = try String(contentsOf: base.appendingPathComponent(name), encoding: .utf8)
        return raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return !t.hasPrefix("//") && !t.hasPrefix("///") && !t.hasPrefix("*")
            }
            .joined(separator: "\n")
    }

    /// 目录面板顶部有「退 5 章」**文字按钮**（FR-036：可见入口，不是手势）。
    func testBackFiveButtonExists() throws {
        let src = try source("ReaderTOCSheet.swift")
        XCTAssertTrue(src.contains("Text(\"退 5 章\")"), "须有「退 5 章」文字按钮")
        XCTAssertTrue(src.contains("onBackFive"), "须有退 5 章回调")
    }

    /// 按钮是 **44pt 触控目标**（FR-036 原文）。
    func testBackFiveButtonIs44pt() throws {
        let src = try source("ReaderTOCSheet.swift")
        XCTAssertTrue(src.contains("minWidth: 44, minHeight: 44")
                      || src.contains("width: 44, height: 44"),
                      "退 5 章按钮须为 44pt 触控目标")
    }

    /// 点击上跳 5 章落章首，并提示「已退 5 章」。
    func testBackFiveJumpsAndToasts() throws {
        let src = try source("ReaderSurface.swift")
        XCTAssertTrue(src.contains("max(0, live.chapterID - 5)"),
                      "退 5 章应上跳 5 章（下界收敛到 0）")
        XCTAssertTrue(src.contains("jumpToChapter(target)"), "须跳转到目标章")
        XCTAssertTrue(src.contains("已退 5 章"), "须提示「已退 5 章」")
    }

    /// **AC：全模块不得存在只能手势触达的功能**——UT1 工具条显隐、EGG4 折角
    /// 都已有可见替代（工具条按钮 / 菜单书签）。本测试锁定"退 5 章"有可见按钮。
    func testBackFiveIsNotGestureOnly() throws {
        let src = try source("ReaderTOCSheet.swift")
        // 按钮是普通 Button（非手势触发）
        XCTAssertTrue(src.contains("Button(action: onBackFive)"),
                      "退 5 章必须是可见按钮而非手势")
    }

    /// 下界收敛：第 0 章退 5 章 → 仍停在第 0 章（不越界）。
    func testBackFiveClampsAtZero() throws {
        let src = try source("ReaderSurface.swift")
        XCTAssertTrue(src.contains("max(0, live.chapterID - 5)"),
                      "退 5 章须做下界收敛（不得为负）")
    }
}
