import XCTest
@testable import InkSightAppUI
import Foundation

/// 目录与进度面板的契约测试（工具条入口不再有空回调）。
final class ReaderTOCContractTests: XCTestCase {

    private func source(_ name: String) throws -> String {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/InkSightAppUI")
        return try String(contentsOf: base.appendingPathComponent(name), encoding: .utf8)
    }

    /// **工具条不再有空回调**：五个按钮全部接到真实行为。
    func testToolbarHasNoEmptyCallbacks() throws {
        let src = try source("ReaderToolbar.swift")
        // 剥离注释后检查 action: {} 形态
        let code = src.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return !t.hasPrefix("//") && !t.hasPrefix("///")
            }
            .joined(separator: "\n")
        XCTAssertFalse(code.contains("action: {}"), "工具条不得有空回调")
        for callback in ["onTOC", "onProgress", "onBookmark", "onSwapVersion", "onSettings"] {
            XCTAssertTrue(code.contains(callback), "工具条须暴露 \(callback)")
        }
    }

    /// 目录：标题来自章节锚点（**不解析正文**，NFR-08），并有诚实空态。
    func testTOCUsesChapterAnchorsAndHonestEmptyState() throws {
        let src = try source("ReaderTOCSheet.swift")
        XCTAssertTrue(src.contains("ChapterAnchor"), "目录须以章节锚点为准（NFR-08）")
        XCTAssertTrue(src.contains("没有可用的章节目录"), "无章节时要有诚实空态")
    }

    /// 目录：当前章高亮 + 可选中。
    func testTOCHighlightsCurrentChapter() throws {
        let src = try source("ReaderTOCSheet.swift")
        XCTAssertTrue(src.contains("currentChapter"), "须标出当前章")
        XCTAssertTrue(src.contains("isSelected"), "当前章应有无障碍选中态")
    }

    /// 进度：位置以 **charOffset** 表达（FR-011：不以页码为准）。
    func testProgressShowsCharOffset() throws {
        let src = try source("ReaderTOCSheet.swift")
        XCTAssertTrue(src.contains("charOffset"), "进度须展示字符偏移")
        XCTAssertTrue(src.contains("字符偏移"), "UI 应明示字符偏移")
    }

    /// 两个自绘浮层都满足 FR-014 四条可用性（44pt / .escape / 36×4 / scrim）。
    func testBothSheetsMeetFourUsabilityRequirements() throws {
        let src = try source("ReaderTOCSheet.swift")
        XCTAssertTrue(src.contains("width: 44, height: 44"), "须有 44pt 关闭按钮")
        XCTAssertTrue(src.contains("accessibilityAction(.escape)"), "须有 .escape")
        XCTAssertTrue(src.contains("width: 36, height: 4"), "须有 36×4 把手")
        XCTAssertTrue(src.contains("onTapGesture"), "scrim 须可点击关闭")
        // 两个 sheet 各一份 → 至少出现两次（目录 + 进度）
        let escapeCount = src.components(separatedBy: "accessibilityAction(.escape)").count - 1
        XCTAssertGreaterThanOrEqual(escapeCount, 2, "目录与进度各自都要有 .escape")
    }

    /// 阅读器把目录/进度接到工具条（真实入口，不再是占位）。
    func testReaderWiresTOCAndProgress() throws {
        let src = try source("ReaderSurface.swift")
        XCTAssertTrue(src.contains("onTOC: { showTOC = true }"), "目录须接真实入口")
        XCTAssertTrue(src.contains("onProgress: { showProgress = true }"), "进度须接真实入口")
        XCTAssertTrue(src.contains("jumpToChapter"), "目录须能真实跳章")
    }

    /// 跳章后落点是**章首 charOffset = 0**（定位铁律，非页码）。
    func testChapterJumpUsesCharOffsetZero() throws {
        let src = try source("ReaderSurface.swift")
        guard let range = src.range(of: "private func jumpToChapter") else {
            return XCTFail("找不到 jumpToChapter")
        }
        let body = String(src[range.lowerBound...].prefix(900))
        XCTAssertTrue(body.contains("recordProgress(at: 0)"),
                      "跳章应把进度设为章首 charOffset = 0")
        XCTAssertFalse(body.contains("pageIndex"), "跳章不得依赖 pageIndex")
    }
}

/// 玻璃唯一入口纪律（D-28）：阅读器内的浮层**不得直接使用 `.regularMaterial` 等 Material**，
/// 必须经 `GlassSurface`（否则绕过白名单与四态收起）。
final class GlassEntryPointContractTests: XCTestCase {

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

    /// 三处浮层都不得直接 background material。
    func testNoDirectMaterialInReaderPanels() throws {
        for file in ["ReaderTOCSheet.swift", "ReaderSurface.swift"] {
            let src = try source(file)
            XCTAssertFalse(src.contains(".regularMaterial"),
                           "\(file) 不得直接使用 .regularMaterial（须经 GlassSurface）")
            XCTAssertFalse(src.contains(".thinMaterial"),
                           "\(file) 不得使用 .thinMaterial")
            XCTAssertFalse(src.contains(".ultraThinMaterial"),
                           "\(file) 不得使用 .ultraThinMaterial")
        }
    }

    /// 三处浮层都经 GlassSurface 绘制。
    func testPanelsUseGlassSurface() throws {
        let toc = try source("ReaderTOCSheet.swift")
        let tocCount = toc.components(separatedBy: "GlassSurface(strength: .l3").count - 1
        XCTAssertGreaterThanOrEqual(tocCount, 2, "目录与进度都应经 GlassSurface(.l3)")

        // 版本对比浮层已抽到独立文件（ReaderSurface 受 0 玻璃结构约束，不得含 GlassSurface）
        let overlay = try source("VersionCompareOverlay.swift")
        XCTAssertTrue(overlay.contains("GlassSurface(strength: .l3"),
                      "版本对比浮层应经 GlassSurface(.l3)")
        // 且 ReaderSurface 本身必须保持 0 玻璃（另由 ReaderContractTests 守）
        let surface = try source("ReaderSurface.swift")
        XCTAssertFalse(surface.contains("GlassSurface("),
                       "ReaderSurface 不得含任何 GlassSurface 代码（正文区 0 玻璃）")
    }
}
