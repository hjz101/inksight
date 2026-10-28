import XCTest
@testable import InkSightAppKit
import InkSightCore
import Foundation

/// 开发包 #5 契约测试（逻辑层）：真实文件导入闭环、进度恢复、CTFrame 不落盘、扫描预算。
final class BookShelfImportTests: XCTestCase {

    // MARK: - 公版夹具（确定性）

    /// 公版风格章节文本（含章节标记，驱动 ChapterScanner）。
    private static let fixtureText = """
    第1章 起风
    春风拂过山岗，草木渐渐苏醒。远处传来牧童的笛声，悠扬而清远。
    林间的鸟雀争相歌唱，仿佛在诉说去冬的往事。

    第2章 又一夜
    夜色渐深，星河低垂。炉火明明灭灭，映照着窗棂上的霜花。
    有人独坐灯下，把一卷旧书翻到末尾。
    """

    private static func fixtureData() -> Data { Data(fixtureText.utf8) }

    // MARK: - 导入闭环（真实链路，可测）

    /// 注入公版 txt `Data` → `ChapterScanner.scan` 产出 `ChapterAnchor` → 切片首章文本 →
    /// `ReaderEngine(chapterText:)` 排版 → 断言 `fr031Passes==true` 且 `pages` 非空
    /// （真实章节被渲染，非 SampleChapter 占位）。
    func testImportClosureRendersRealChapter() throws {
        let data = Self.fixtureData()
        let scan = ChapterScanner.scan(data)
        XCTAssertGreaterThan(scan.chapters.count, 0, "应至少扫描出一章")
        let first = scan.chapters[0]
        let text = BookShelfStore.sliceChapter(from: data, anchor: first)
        XCTAssertFalse(text.isEmpty, "切片首章文本不应为空")

        let engine = ReaderEngine(chapterText: text)
        XCTAssertTrue(engine.typeset.fr031Passes, "导入真实章节应 fr031Passes（FR-031 零位移）")
        XCTAssertGreaterThan(engine.pageCount, 0, "真实章节应被渲染为至少一页（非 SampleChapter 占位）")
    }

    /// 导入后 `BookShelfItem` 应存章节锚点 + fileURL，正文不随主表进内存（NFR-08）。
    func testImportStoresChaptersAndFileURL() throws {
        let data = Self.fixtureData()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-import-\(UUID().uuidString).txt")
        try data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = BookShelfStore()
        let item = try store.importLocalBook(bookID: "imp-1", title: "测试书", fileURL: tmp)
        XCTAssertEqual(item.chapterCount, item.chapters.count, "章节数应与锚点数一致")
        XCTAssertNotNil(item.fileURL, "应记录文件 URL 以便按需切片")
        XCTAssertEqual(item.source, .localImport)
    }

    // MARK: - 进度恢复（导入真实书 → 写 charOffset → 重开二分落点 ≤1 屏）

    func testImportThenProgressRecoveryWithinOneScreen() throws {
        let data = Self.fixtureData()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-import-\(UUID().uuidString).txt")
        try data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = BookShelfStore()
        let item = try store.importLocalBook(bookID: "imp-2", title: "测试书", fileURL: tmp)
        guard let text = store.chapterText(for: item, chapterIndex: 0), !text.isEmpty else {
            XCTFail("按需切片取章失败"); return
        }

        let progressStore = ReadingProgressStore()
        let engine1 = ReaderEngine(bookID: item.bookID, chapterID: 0, chapterText: text, progressStore: progressStore)
        guard let last = engine1.typeset.lines.last else { XCTFail(); return }
        let target = (last.charOffset + last.charLength) / 2   // 章中偏移
        engine1.recordProgress(at: target)

        // 重开（同 bookID + 同 store，模拟再次进入阅读器）
        let engine2 = ReaderEngine(bookID: item.bookID, chapterID: 0, chapterText: text, progressStore: progressStore)
        let progress = engine2.currentProgress()
        XCTAssertNotNil(progress, "应从 store 读出进度")
        XCTAssertEqual(progress?.charOffset, target)

        let pageIdx = engine2.resolvePageIndex(for: target)
        let landing = engine2.landingCharOffset(for: target)
        guard let page = engine2.page(at: pageIdx) else { XCTFail(); return }
        XCTAssertLessThanOrEqual(landing, target, "恢复落点不得晚于目标偏移")
        XCTAssertLessThan(target, landing + page.anchor.charLength, "目标偏移须落在恢复页范围内（误差 ≤1 屏）")
    }

    // MARK: - CTFrame 不落盘（合规四禁令）

    /// 导入与渲染路径无 `CTFramesetterCreateFrame` / `CTFrameCache` / 写正文到磁盘。
    func testBookShelfStoreNoDiskWritesOrCTFrame() throws {
        let url = try sourceURL("BookShelfStore.swift", inUI: false)
        let src = stripComments(try String(contentsOf: url, encoding: .utf8))
        XCTAssertFalse(src.contains("CTFramesetterCreateFrame"), "导入路径不得创建 CTFrame")
        XCTAssertFalse(src.contains("CTFrameCache"), "导入路径不得触碰 CTFrameCache")
        XCTAssertFalse(src.contains("write(to:"), "导入路径不得写正文到磁盘")
        XCTAssertFalse(src.contains("write(toFile:"), "导入路径不得写正文到磁盘")
    }

    // MARK: - 20MB 扫描预算（缩放至 2MB 以控制单测耗时；判据同 Core：debug 硬闸不卡死）

    func testLargeScanBudgetDoesNotChoke() {
        let chunk = Self.fixtureData()
        var big = Data()
        let targetBytes = 2 * 1024 * 1024
        var i = 0
        while big.count < targetBytes {
            big.append(Data("第\(i)章 段落\n".utf8))
            big.append(chunk)
            big.append(Data([0x0A]))
            i += 1
        }
        XCTAssertGreaterThan(big.count, targetBytes / 2, "应生成足够大的夹具")

        let store = BookShelfStore()
        let start = Date()
        let item = store.importLocalBook(bookID: "big", title: "", fileData: big)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertGreaterThan(item.chapterCount, 1, "大文件应扫描出多章")
        XCTAssertLessThan(elapsed, 3.0, "debug 构建硬闸：2MB 扫描不应超 3s（不卡死）")
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
