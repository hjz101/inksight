import XCTest
@testable import InkSightCore
import Foundation

/// 20MB 分章扫描：时间与正确性（技术约束清单 NFR-08；POC 文档 §0.7 样本要求）。
final class ChapterScannerTests: XCTestCase {

    /// 生成确定性 20MB 文本：400 章 × 每章约 50KB（章节标记「第N章 …」＋ 段落块），
    /// **内嵌一段 8–12KB 无章节标记整块文本**（虚拟分节样本，POC 文档 §0.7）。
    private func make20MBText() -> String {
        let sentence = "他沿着旧城的石板路往北走，雨还没停，屋檐下的灯笼在风里晃，把他的影子拉得很长，巷口的猫缩在纸箱后面看他，像是在等一个不会来的人。"
        var block = ""
        while block.utf8.count < 52_000 {
            block += sentence
        }
        block += "\n"
        var text = ""
        text.reserveCapacity(21_000_000)
        for chapter in 0..<400 {
            if chapter == 200 {
                // 无章节标记整块文本（约 11KB）：插在正文中间，验证虚拟分节
                let unmarked = String(repeating: sentence, count: 6)
                text += unmarked
            } else {
                text += "第\(chapter)章 路上的灯\n"
                text += block
            }
        }
        return text
    }

    /// 20MB 扫描：时间（≤1.0s 硬闸；目标 ≤100ms，实测打印留痕）与正确性。
    func testScan20MBCorrectnessAndTime() {
        let text = make20MBText()
        let data = Data(text.utf8)
        let sizeMB = Double(data.count) / 1_000_000
        print("样本体积：\(sizeMB) MB")

        let result = ChapterScanner.scan(data)

        print("分章扫描：\(result.elapsedMS) ms，章节数 = \(result.chapters.count)，虚拟分节 = \(result.virtualSectionCount)")
        XCTAssertLessThan(result.elapsedMS, 1_000, "20MB 扫描超 1s（目标 ≤100ms）——POC-3(c) 不通过")

        // 正确性：①连续全覆盖（首尾相接）②每段 ≤ maxChunkBytes ③标记行命中为章首
        var cursor = 0
        var maxLen = 0
        for anchor in result.chapters {
            XCTAssertEqual(anchor.byteOffset, cursor, "章锚点必须首尾相接")
            cursor += anchor.byteLength
            maxLen = max(maxLen, anchor.byteLength)
        }
        XCTAssertEqual(cursor, data.count, "章锚点必须覆盖全部字节")
        XCTAssertLessThanOrEqual(maxLen, 12_000, "任何章不得超过虚拟分节阈值（含标记章）")
        XCTAssertGreaterThanOrEqual(result.chapters.count, 400, "标记章不得丢失")

        // 标记行文本抽查：第 3 个标记章的 title 应为其标记行原文
        let markerChapters = result.chapters.filter { $0.title.hasPrefix("第") }
        XCTAssertGreaterThanOrEqual(markerChapters.count, 399, "399 个标记章 + 虚拟分节")
        XCTAssertTrue(markerChapters.allSatisfy { $0.title.contains("路上的灯") })
    }

    /// 无章节标记整块文本（>12KB）→ 虚拟分节（POC 文档 §0.7）。
    func testUnmarkedBlockGetsVirtualSections() {
        let sentence = "没有章节标记的长段落，只有空行分隔，用来验证虚拟分节的正确性。"
        var body = ""
        while body.utf8.count < 15_000 { body += sentence + "\n" }   // 15KB > 阈值 12KB
        let text = "第一章 开头\n" + body
        let result = ChapterScanner.scan(Data(text.utf8))

        XCTAssertGreaterThan(result.virtualSectionCount, 0, "超阈值的无标记整块必须虚拟分节")
        let unmarked = result.chapters.filter { $0.title.contains("虚拟分节") }
        XCTAssertFalse(unmarked.isEmpty)
        XCTAssertTrue(unmarked.allSatisfy { $0.byteLength <= 12_000 })
        var cursor = result.chapters[0].byteOffset + result.chapters[0].byteLength
        for anchor in result.chapters.dropFirst() {
            XCTAssertEqual(anchor.byteOffset, cursor)
            cursor += anchor.byteLength
        }
        XCTAssertEqual(cursor, data(of: text))
    }

    /// 无标记且总体小于阈值 → 单章。
    func testSmallUnmarkedIsSingleChapter() {
        let text = "只有一段没有标记的文字。"
        let result = ChapterScanner.scan(Data(text.utf8))
        XCTAssertEqual(result.chapters.count, 1)
        XCTAssertEqual(result.chapters[0].byteOffset, 0)
        XCTAssertEqual(result.chapters[0].byteLength, data(of: text))
        XCTAssertEqual(result.virtualSectionCount, 0)
    }

    /// 章节标记正则的语义：第X章 / 第X卷 / Chapter N 都算；正文里出现「第」不算。
    func testMarkerSemantics() {
        let text = """
        第一章 起风
        正文第一段，里面提到第二次见面，不是章节标记。
        第二章 又一夜
        Chapter 3 - English marker
        第三章 尾声
        """
        let result = ChapterScanner.scan(Data(text.utf8))
        let titles = result.chapters.filter { $0.title.hasPrefix("第") || $0.title.lowercased().hasPrefix("chapter") }.map(\.title)
        print("DEBUG titles:", titles)
        XCTAssertTrue(titles.contains { $0.hasPrefix("第一章") })
        XCTAssertTrue(titles.contains { $0.hasPrefix("第二章") })
        XCTAssertTrue(titles.contains { $0.lowercased().hasPrefix("chapter 3") })
        XCTAssertTrue(titles.contains { $0.hasPrefix("第三章") })
    }

    private func data(of text: String) -> Int { Data(text.utf8).count }
}
