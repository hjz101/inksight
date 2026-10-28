import XCTest
@testable import InkSightAppKit
import InkSightCore
import CoreText
import Foundation

/// 开发包 #4 契约测试（逻辑层）：FR-031 零位移、进度恢复（≤1 屏）、五式翻页配置、CTFrame 不落盘。
final class ReaderEngineTests: XCTestCase {

    private func makeEngine(progressStore: ReadingProgressStore = ReadingProgressStore()) -> ReaderEngine {
        ReaderEngine(bookID: SampleChapter.bookID,
                     chapterID: SampleChapter.chapterID,
                     chapterText: SampleChapter.text,
                     progressStore: progressStore)
    }

    /// FR-031 零位移（排版侧）：Typesetter 必须保证 maxDelta ≤0.5 且 fr031Passes。
    func testTypesetFr031Passes() {
        let engine = makeEngine()
        XCTAssertTrue(engine.typeset.fr031Passes,
                      "Typesetter.fr031Passes 必须为 true（FR-031 零位移判据）")
        XCTAssertLessThanOrEqual(engine.typeset.fr031MaxDelta, 0.5,
                                 "全章最大 |actual − predicted| 应 ≤0.5pt")
    }

    /// FR-031 零位移（渲染侧）：`CoreTextLineCompositor` 重建的 `CTLine` 实测宽度，
    /// 须与 `TypesetLine.predictedWidth` 之差 ≤0.5pt（逐行自绘不引入重排位移）。
    func testCompositorReproducesZeroDisplacementWidths() {
        let engine = makeEngine()
        let comp = CoreTextLineCompositor(text: engine.chapterText, typography: engine.typography)
        var maxDelta: Double = 0
        for line in engine.typeset.lines {
            let ctLine = comp.line(for: line)
            var ascent: CGFloat = 0, descent: CGFloat = 0, lead: CGFloat = 0
            let actual = CTLineGetTypographicBounds(ctLine, &ascent, &descent, &lead)
            maxDelta = max(maxDelta, abs(Double(actual) - line.predictedWidth))
        }
        XCTAssertLessThanOrEqual(maxDelta, 0.5,
                                 "渲染侧重建 CTLine 实测宽与 predictedWidth 之差应 ≤0.5pt（FR-031）")
    }

    /// 示例章节应在默认容器下分页为多页（恢复跨页才有意义）。
    func testSampleChapterPaginatesIntoMultiplePages() {
        let engine = makeEngine()
        XCTAssertGreaterThan(engine.pageCount, 1,
                             "示例章节应在默认容器下分页为多页，以验证跨页恢复")
    }

    /// 进度恢复：进入阅读器时读同一 store，二分定位落点须落在含目标偏移的页内（误差 ≤1 屏）。
    func testProgressRecoveryWithinOneScreen() {
        let store = ReadingProgressStore()
        let engine1 = makeEngine(progressStore: store)

        guard let last = engine1.typeset.lines.last else { XCTFail("无行"); return }
        let totalChars = last.charOffset + last.charLength
        let target = totalChars / 2   // 章中某个 UTF-16 偏移

        engine1.recordProgress(at: target)

        // 新引擎（同一 store，模拟"再次进入阅读器"）恢复
        let engine2 = makeEngine(progressStore: store)
        let progress = engine2.currentProgress()
        XCTAssertNotNil(progress, "应能从 store 读出进度")
        XCTAssertEqual(progress?.charOffset, target, "恢复的 charOffset 应与落盘一致")

        let pageIdx = engine2.resolvePageIndex(for: target)
        let landing = engine2.landingCharOffset(for: target)
        guard let page = engine2.page(at: pageIdx) else { XCTFail("页缺失"); return }

        // 误差 ≤1 屏：落点为页首，目标偏移落在该页 [landing, landing+charLength) 内
        XCTAssertLessThanOrEqual(landing, target, "恢复落点不得晚于目标偏移")
        XCTAssertLessThan(target, landing + page.anchor.charLength,
                          "目标偏移须落在恢复页范围内（误差 ≤1 屏）")

        // 定位铁律：恢复路径不依赖 pageIndex（页由 charOffset 二分得出）
        XCTAssertEqual(engine2.recoverPageIndex(), pageIdx)
    }

    /// 定位铁律（类型层保证）：进度落盘只含 charOffset＋fingerprint，无 pageIndex。
    func testRecordedProgressHasNoPageIndex() {
        let engine = makeEngine()
        engine.recordProgress(at: 100)
        let p = engine.currentProgress()
        XCTAssertEqual(p?.charOffset, 100)
        XCTAssertNotNil(p?.fingerprint)
    }

    /// ReaderConfig 默认：横向滚动翻页；NFR-06 空闲 3s 停渲染。
    func testReaderConfigDefaults() {
        XCTAssertEqual(ReaderConfig.default.pageTurnMode, .scroll,
                       "派单 default none or scroll，取 scroll")
        XCTAssertEqual(ReaderConfig.default.idleDisplayLinkStopSeconds, 3,
                       "NFR-06：空闲 3s 后停止渲染循环")
    }

    /// FR-008 五式翻页齐全。
    func testPageTurnModeHasFiveCases() {
        XCTAssertEqual(PageTurnMode.allCases.count, 5)
        XCTAssertTrue(PageTurnMode.allCases.contains(.none))
        XCTAssertTrue(PageTurnMode.allCases.contains(.scroll))
        XCTAssertTrue(PageTurnMode.allCases.contains(.vertical))
        XCTAssertTrue(PageTurnMode.allCases.contains(.flip))
        XCTAssertTrue(PageTurnMode.allCases.contains(.curl))
    }

    /// CTFrame 不落盘（合规四禁令）：渲染路径不得创建 CTFrame、不得触碰 CTFrameCache、
    /// 不得有任何磁盘写入。源码（去注释）断言，避免注释假阳性（#2 教训）。
    func testCompositorProducesNoCTFrameAndNoDiskWrites() throws {
        let url = try sourceURL("CoreTextLineCompositor.swift", inUI: false)
        let src = stripComments(try String(contentsOf: url, encoding: .utf8))
        XCTAssertFalse(src.contains("CTFramesetterCreateFrame"),
                       "渲染路径不得创建 CTFrame（glyph＋字体可还原 Unicode，视同正文）")
        XCTAssertFalse(src.contains("CTFrameCache"),
                       "渲染路径不得触碰 CTFrameCache（按需逐行成行，连缓存都不需要）")
        XCTAssertFalse(src.contains("FileManager"),
                       "渲染路径不得有任何磁盘写入")
        XCTAssertFalse(src.contains("write(to:"),
                       "渲染路径不得落盘")
    }

    // MARK: - 源码路径 / 注释剥离（测试工具）

    private func sourceURL(_ name: String, inUI: Bool) throws -> URL {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/InkSightAppKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // InkSightApp
        let sub = inUI ? "Sources/InkSightAppUI" : "Sources/InkSightAppKit"
        return base.appendingPathComponent(sub).appendingPathComponent(name)
    }

    /// 剥离 `//` 行注释与 `/* */` 块注释（#2 教训：注释里的 GlassSurface/CTFrame 不能算引用）。
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
