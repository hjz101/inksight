import XCTest
@testable import InkSightAppUI
import Foundation

/// D-100：标签管理与方案分享的 **UI 接线**测试（能力就绪 → 真的有入口）。
final class UIBindingTests: XCTestCase {

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

    /// 标签管理有 UI 入口（墨迹页工具栏）。
    func testTagManagementEntry() throws {
        let notes = try source("NotesScreen.swift")
        XCTAssertTrue(notes.contains("TagManagementView"), "墨迹页须挂标签管理")
        XCTAssertTrue(notes.contains("标签管理"), "须有可见入口文案")

        let view = try source("TagManagementView.swift")
        XCTAssertTrue(view.contains("renameTag"), "UI 须接重命名")
        XCTAssertTrue(view.contains("deleteTag"), "UI 须接删除")
        XCTAssertTrue(view.contains("tagUsage"), "UI 须显示使用统计")
    }

    /// 标签删除**保留划线**（UI 文案须如实说明）。
    func testDeleteTagKeepsHighlightMessage() throws {
        let view = try source("TagManagementView.swift")
        XCTAssertTrue(view.contains("划线保留"), "须向用户说明删标签不影响划线")
    }

    /// 标签管理诚实空态。
    func testTagManagementEmptyState() throws {
        let view = try source("TagManagementView.swift")
        XCTAssertTrue(view.contains("还没有标签"), "无标签须诚实说明")
    }

    /// 方案分享有 UI 入口（我页）。
    func testSchemeSharingEntry() throws {
        let me = try source("PlaceholderScreens.swift")
        XCTAssertTrue(me.contains("SchemeSharingView"), "我页须挂方案分享")
        XCTAssertTrue(me.contains("阅读方案"), "须有可见入口文案")
    }

    /// 方案分享：保存/导入/分享三能力都接了。
    func testSchemeSharingCapabilities() throws {
        let view = try source("SchemeSharingView.swift")
        XCTAssertTrue(view.contains("store.save"), "须能保存方案")
        XCTAssertTrue(view.contains("ReaderSchemeCodec.decode"), "须能导入方案")
        XCTAssertTrue(view.contains("ReaderSchemeCodec.encode"), "须能导出/分享")
    }

    /// 导入失败**明确报错**（不静默回落）。
    func testImportFailureSurfacesReason() throws {
        let view = try source("SchemeSharingView.swift")
        XCTAssertTrue(view.contains("errorDescription"), "须显示具体错误原因")
        XCTAssertTrue(view.contains("不会静默忽略"), "须向用户声明不静默")
    }

    /// 方案**不含正文**声明。
    func testSchemeDoesNotClaimToIncludeContent() throws {
        let view = try source("SchemeSharingView.swift")
        XCTAssertTrue(view.contains("不含任何书籍内容"), "须声明方案不含正文")
    }
}
