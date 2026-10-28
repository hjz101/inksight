import XCTest
@testable import InkSightAppUI
import InkSightAppKit
import InkSightCore
import SwiftUI
import Foundation

/// 开发包 #4 契约测试（UI 层）：正文区 0 玻璃的结构保证（源码级断言，去注释避免 #2 假阳性）。
final class ReaderContractTests: XCTestCase {

    /// 0 玻璃（结构保证）：`ReaderSurfaceView` 源码（去除注释后）不得引用 `GlassSurface` /
    /// `GlassStrength` / `.glassEffect`——全 App 玻璃唯一入口是 `GlassSurface`，正文视图进不来。
    ///
    /// 注意：注释里可以"提到"玻璃（如说明边界），故先剥离 `//` 与 `/* */` 再断言（#2 教训）。
    func testReaderSurfaceSourceHasNoGlassReference() throws {
        let url = try sourceURL("ReaderSurface.swift", inUI: true)
        let src = stripComments(try String(contentsOf: url, encoding: .utf8))
        XCTAssertFalse(src.contains("GlassSurface"),
                       "正文视图源码（去注释后）不得引用 GlassSurface")
        XCTAssertFalse(src.contains("GlassStrength"),
                       "正文视图源码（去注释后）不得引用 GlassStrength")
        XCTAssertFalse(src.contains("glassEffect"),
                       "正文视图源码（去注释后）不得调用 .glassEffect")
    }

    /// 正文背景为**不透明纯色**纸面（0 玻璃 0 backdrop），颜色由主题决定（FR-010）。
    ///
    /// D-71 变更：此前断言硬编码 `Color(white: 0.98)`；FR-010 落地后纸面色改为按主题取
    /// （`ReaderPageCanvas.color(hex: theme.backgroundHex)`）。**纪律不变**——仍必须是不透明
    /// 纯色、不得进玻璃容器；变的是「颜色来源从常量改为主题」。
    func testReaderSurfaceUsesOpaquePaperBackground() throws {
        let url = try sourceURL("ReaderSurface.swift", inUI: true)
        let src = stripComments(try String(contentsOf: url, encoding: .utf8))
        XCTAssertTrue(src.contains("theme.backgroundHex"),
                      "正文背景应按主题取不透明纯色（FR-010）")
        XCTAssertTrue(src.contains("ignoresSafeArea"),
                      "纸面应铺满全屏")
        XCTAssertFalse(src.contains("GlassEffectContainer"),
                       "正文视图不得进入任何玻璃容器")
        XCTAssertFalse(src.contains(".glassEffect"),
                       "正文视图不得使用 glassEffect")
    }

    /// 0 玻璃（书架→阅读器路径）：`ReaderSurfaceView` 接入书架，但不得被任何 `GlassSurface`
    /// 内容闭包包裹（阅读页 0 玻璃由类型层保证）。书架自身可用 L2 玻璃（白名单：继续阅读卡），
    /// 但阅读器承接不得进玻璃闭包。
    func testShelfScreenReaderPathNotWrappedInGlass() throws {
        let url = try sourceURL("PlaceholderScreens.swift", inUI: true)
        let src = stripComments(try String(contentsOf: url, encoding: .utf8))
        XCTAssertTrue(src.contains("ReaderSurfaceView(engine:"),
                      "书架应接入 ReaderSurfaceView 渲染真实章节")
        XCTAssertTrue(glassClosuresExcludeReader(src),
                      "ReaderSurfaceView 不得出现在任何 GlassSurface 内容闭包内（阅读页 0 玻璃）")
    }

    /// 括号匹配：每个 `GlassSurface` 的内容闭包 `{ ... }` 内不得含 `ReaderSurfaceView`。
    private func glassClosuresExcludeReader(_ src: String) -> Bool {
        var search = src.startIndex
        while let range = src.range(of: "GlassSurface", range: search..<src.endIndex) {
            let after = range.upperBound
            guard let open = src.range(of: "{", range: after..<src.endIndex)?.lowerBound else { return false }
            var depth = 0
            var j = open
            var close: String.Index?
            while j < src.endIndex {
                let c = src[j]
                if c == "{" { depth += 1 }
                else if c == "}" {
                    depth -= 1
                    if depth == 0 { close = j; break }
                }
                j = src.index(after: j)
            }
            guard let close else { return false }
            let inner = String(src[src.index(after: open)..<close])
            if inner.contains("ReaderSurfaceView") { return false }
            search = src.index(after: close)
        }
        return true
    }

    /// 公开 API 维持 `onExit` 单一退出回调（骨架契约不变），且不暴露玻璃强度/交互字段。
    func testReaderSurfacePublicAPIHasOnlyOnExitAndEngine() {
        let view = ReaderSurfaceView(onExit: {})
        let labels = Mirror(reflecting: view).children.compactMap(\.label)
        XCTAssertTrue(labels.contains("onExit"), "公开 API 应保留退出回调")
        XCTAssertTrue(labels.contains("engine"), "应可注入阅读引擎")
        XCTAssertFalse(labels.contains("strength"), "正文视图不得持有玻璃强度")
        XCTAssertFalse(labels.contains("interactive"), "正文视图不得持有玻璃交互开关")
    }

    /// 注入引擎后（convenience init）可正常构造；engine==nil 时退化为诚实空态，不崩溃。
    func testReaderSurfaceEngineInitDoesNotCrash() {
        let engine = ReaderEngine(bookID: SampleChapter.bookID,
                                 chapterID: SampleChapter.chapterID,
                                 chapterText: SampleChapter.text)
        let withEngine = ReaderSurfaceView(engine: engine, onExit: {})
        let mirror = Mirror(reflecting: withEngine)
        XCTAssertTrue(mirror.children.contains(where: { $0.label == "engine" }))
        // 诚实空态路径
        _ = ReaderSurfaceView(onExit: {})
    }

    /// 0 玻璃（数据层结构保证）：开发包 #6 新增的 `TypographyPresetStore` / `PaginationCoordinator`
    /// 属数据层，源码（去注释后）不得引用 `GlassSurface` / `GlassStrength` / `.glassEffect`。
    func testPresetStoreAndCoordinatorSourceHaveNoGlassReference() throws {
        for name in ["TypographyPresetStore.swift", "PaginationCoordinator.swift"] {
            let url = try sourceURL(name, inUI: false)
            let src = stripComments(try String(contentsOf: url, encoding: .utf8))
            XCTAssertFalse(src.contains("GlassSurface"), "\(name) 不得引用 GlassSurface")
            XCTAssertFalse(src.contains("GlassStrength"), "\(name) 不得引用 GlassStrength")
            XCTAssertFalse(src.contains("glassEffect"), "\(name) 不得调用 .glassEffect")
        }
    }

    /// 0 玻璃（MeScreen 结构保证）：开发包 #6 把"研究态·不落地"落定为持久化预设编辑，
    /// 但 `MeScreen` 仍不得引用玻璃（阅读设置不是正文区，但本包纪律要求新增界面零玻璃）。
    func testMeScreenSourceHasNoGlassReference() throws {
        let url = try sourceURL("PlaceholderScreens.swift", inUI: true)
        let src = stripComments(try String(contentsOf: url, encoding: .utf8))
        guard let start = src.range(of: "struct MeScreen") else {
            XCTFail("找不到 struct MeScreen"); return
        }
        // MeScreen 为文件末尾最后一个 struct，扫描至文件结尾即可覆盖其全部内容
        let meScreenSrc = String(src[start.lowerBound...])
        XCTAssertFalse(meScreenSrc.contains("GlassSurface"), "MeScreen 不得引用 GlassSurface")
        XCTAssertFalse(meScreenSrc.contains("GlassStrength"), "MeScreen 不得引用 GlassStrength")
        XCTAssertFalse(meScreenSrc.contains("glassEffect"), "MeScreen 不得调用 .glassEffect")
    }

    /// 开发包 #8：阅读器须有**明确的公开换排版入口**（源码级断言，去注释后扫描）。
    /// 换排版 → 落点按同一 `charOffset` 重新二分定位，是「机制本体接进真实链路」的公开门面。
    func testReaderSurfaceHasPublicApplyTypographyEntry() throws {
        let url = try sourceURL("ReaderSurface.swift", inUI: true)
        let src = stripComments(try String(contentsOf: url, encoding: .utf8))
        XCTAssertTrue(src.contains("public func applyTypography("),
                      "阅读器须提供公开的换排版入口（开发包 #8）")
        XCTAssertTrue(src.contains("ReaderSession"), "阅读器须经会话承载可替换的引擎")
    }

    // MARK: - 源码路径 / 注释剥离（测试工具）

    private func sourceURL(_ name: String, inUI: Bool) throws -> URL {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/InkSightAppUITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // InkSightApp
        let sub = inUI ? "Sources/InkSightAppUI" : "Sources/InkSightAppKit"
        return base.appendingPathComponent(sub).appendingPathComponent(name)
    }

    private func stripComments(_ source: String) -> String {
        var out = ""
        var i = source.startIndex
        let s = source
        while i < s.endIndex {
            if s[i...].hasPrefix("/*") {
                if let end = s[i...].range(of: "*/") { i = end.upperBound; continue }
                break
            }
            if s[i...].hasPrefix("//") {
                if let nl = s[i...].firstIndex(of: "\n") { i = nl; continue }
                break
            }
            out.append(s[i])
            i = s.index(after: i)
        }
        return out
    }
}
