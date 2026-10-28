import XCTest
@testable import InkSightAppUI
import Foundation

/// FR-014 结构边界：阅读工具条（chrome 层）可用玻璃，**正文画布内不得有玻璃**。
final class ReaderToolbarContractTests: XCTestCase {

    /// #filePath = .../InkSightApp/Tests/InkSightAppUITests/<本文件>.swift
    private func source(_ name: String) throws -> String {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // InkSightAppUITests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // InkSightApp（包根）
            .appendingPathComponent("Sources/InkSightAppUI")
        return try String(contentsOf: base.appendingPathComponent(name), encoding: .utf8)
    }

    /// 剥离注释（避免注释里提到 GlassSurface 造成误判）。
    private func stripComments(_ src: String) -> String {
        src.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return !t.hasPrefix("//") && !t.hasPrefix("///") && !t.hasPrefix("*")
            }
            .joined(separator: "\n")
    }

    /// 阅读工具条是**玻璃白名单成员**（DESIGN D-28「浮层与工具栏」）。
    func testToolbarUsesGlassSurface() throws {
        let src = stripComments(try source("ReaderToolbar.swift"))
        XCTAssertTrue(src.contains("GlassSurface"), "阅读工具条应经唯一玻璃入口绘制")
        XCTAssertFalse(src.contains(".glassEffect("), "不得绕过 GlassSurface 直接调 glassEffect")
    }

    /// 工具条必须接四态收起参数（FR-014 P0 验收项）。
    func testToolbarSupportsPresentationState() throws {
        let src = stripComments(try source("ReaderToolbar.swift"))
        XCTAssertTrue(src.contains("presentation"), "工具条须支持四态收起")
        XCTAssertTrue(src.contains("GlassPresentationState"), "须用统一四态类型")
    }

    /// **正文画布内不得有玻璃**：`ReaderPageCanvas` 是正文渲染，必须 0 玻璃。
    func testReaderCanvasHasNoGlass() throws {
        let src = stripComments(try source("ReaderSurface.swift"))
        // 找到 ReaderPageCanvas 结构体内的内容
        guard let start = src.range(of: "struct ReaderPageCanvas") else {
            return XCTFail("找不到 ReaderPageCanvas")
        }
        let canvasSrc = String(src[start.lowerBound...])
        XCTAssertFalse(canvasSrc.contains("GlassSurface"),
                       "正文画布不得引用 GlassSurface")
        XCTAssertFalse(canvasSrc.contains("glassEffect"),
                       "正文画布不得调用 glassEffect")
        XCTAssertFalse(canvasSrc.contains("GlassEffectContainer"),
                       "正文画布不得进玻璃容器")
    }

    /// 工具条恒含「书签」入口（FR-011 与 EGG4 关态联动：加书签走工具条）。
    func testToolbarHasBookmarkEntry() throws {
        let src = try source("ReaderToolbar.swift")
        XCTAssertTrue(src.contains("书签"), "工具条必须恒含书签入口")
        XCTAssertTrue(src.contains("onBookmark"), "须有书签回调")
    }

    /// 工具条恒含「换一个版本」主路径（FR-018）。
    func testToolbarHasVersionSwapEntry() throws {
        let src = try source("ReaderToolbar.swift")
        XCTAssertTrue(src.contains("换一个版本"), "工具条恒含换一个版本（FR-018 主路径）")
    }
}
