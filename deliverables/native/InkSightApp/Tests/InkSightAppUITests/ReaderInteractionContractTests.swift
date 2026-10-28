import XCTest
@testable import InkSightAppUI
@testable import InkSightAppKit
import CoreGraphics

/// FR-014 UIT1（工具条显隐）与 FR-018 书架回写 的结构契约测试。
final class ReaderInteractionContractTests: XCTestCase {

    private func readerSource() throws -> String {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/InkSightAppUI")
        let raw = try String(contentsOf: base.appendingPathComponent("ReaderSurface.swift"),
                             encoding: .utf8)
        return raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return !t.hasPrefix("//") && !t.hasPrefix("///") && !t.hasPrefix("*")
            }
            .joined(separator: "\n")
    }

    /// UIT1：点按正文中央切显隐，且**无自动恢复定时器**（DESIGN：6 秒自动恢复已被否决）。
    func testUIT1IsCenterTapOnly() throws {
        let src = try readerSource()
        XCTAssertTrue(src.contains("SpatialTapGesture"), "UIT1 应由点按手势触发")
        XCTAssertTrue(src.contains("isCenterTap"), "须有正文中央判定")
        // 否决策略：不得引入自动恢复（"6 秒自动恢复"已在 DESIGN 被否决）
        XCTAssertFalse(src.contains("autoRestore"), "不得实现自动恢复")
        XCTAssertFalse(src.contains("toolbarAutoHide"), "不得实现自动隐藏")
    }

    /// 手势期间进入 `.gesture`（纯色降级），结束 120ms 淡回。
    func testUIT1UsesGesturePresentation() throws {
        let src = try readerSource()
        XCTAssertTrue(src.contains(".gesture"), "手势期间应进入 gesture 态")
        XCTAssertTrue(src.contains("restoreDuration"), "结束后按 120ms 恢复")
    }

    /// 工具条显隐为直切（A 档：`transition(.identity)`，不用系统动画）。
    func testToolbarToggleIsDirectCut() throws {
        let src = try readerSource()
        XCTAssertTrue(src.contains(".transition(.identity)"), "显隐应直切（A 档）")
    }

    /// FR-018：切换版本后回写书架 `lastReadAnchor`（4 字段，无 pageIndex）。
    func testVersionSwitchWritesBackShelfAnchor() throws {
        let src = try readerSource()
        XCTAssertTrue(src.contains("shelf.recordProgress"), "切换版本后应回写书架锚点")
        XCTAssertTrue(src.contains("ReadingProgress(bookID:"), "回写用 4 字段进度模型")
        // 回写内容不得含 pageIndex
        let writebackBlock = src.components(separatedBy: "shelf.recordProgress").last ?? ""
        XCTAssertFalse(writebackBlock.prefix(400).contains("pageIndex"),
                       "书架锚点不得含 pageIndex（定位铁律）")
    }
}
