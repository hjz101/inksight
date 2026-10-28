import XCTest
@testable import InkSightAppKit

/// FR-018 同书多副本对齐契约测试。
final class VersionAlignmentTests: XCTestCase {

    private func candidate(_ id: String, score: Double,
                           label: String = VersionCandidate.defaultVersionLabel) -> VersionCandidate {
        VersionCandidate(id: id, fileName: "\(id).txt", versionLabel: label,
                         fileSizeBytes: 2_200_000, matchScore: score)
    }

    /// **精确对齐**：首尾指纹都匹配 → `.exact`，偏移保持。
    func testExactAlignmentWhenFingerprintsMatch() {
        let head = String(repeating: "开头文字", count: 60)   // >200 字
        let tail = String(repeating: "结尾文字", count: 60)
        let chapter = head + String(repeating: "中间内容", count: 200) + tail

        let result = VersionAlignmentEngine.align(
            sourceOffset: 1234, sourceChapterLength: (chapter as NSString).length,
            sourceHead: String((chapter as NSString).substring(to: 200)),
            sourceTail: String((chapter as NSString).substring(from: (chapter as NSString).length - 200)),
            targetChapterText: chapter, targetChapterTitle: "第一章"
        )
        guard case .exact(let offset) = result else {
            return XCTFail("首尾指纹匹配应为 exact，实际：\(result)")
        }
        XCTAssertEqual(offset, 1234, "精确对齐时偏移保持")
        XCTAssertEqual(result.displayText, "位置精确对齐")
    }

    /// **降级为百分比**：指纹不匹配 → `.approximate`，且**明示近似比例**。
    func testApproximateAlignmentWhenFingerprintsDiffer() {
        let target = String(repeating: "完全不同的正文内容", count: 100)
        let result = VersionAlignmentEngine.align(
            sourceOffset: 500, sourceChapterLength: 1000,
            sourceHead: "原始开头", sourceTail: "原始结尾",
            targetChapterText: target, targetChapterTitle: "第一章"
        )
        guard case .approximate(let offset, let percent) = result else {
            return XCTFail("指纹不匹配应降级为 approximate，实际：\(result)")
        }
        XCTAssertEqual(percent, 50, accuracy: 0.01, "源偏移 500/1000 = 50%")
        XCTAssertGreaterThan(offset, 0)
        XCTAssertFalse(result.isExact)
        XCTAssertTrue(result.displayText.contains("近似对齐"), "必须明示近似对齐")
        XCTAssertTrue(result.displayText.contains("%"), "必须明示百分比")
    }

    /// 空目标 → `.unavailable`（章节缺失）。
    func testUnavailableWhenTargetEmpty() {
        let result = VersionAlignmentEngine.align(
            sourceOffset: 100, sourceChapterLength: 1000,
            sourceHead: "a", sourceTail: "b",
            targetChapterText: "", targetChapterTitle: "第一章"
        )
        XCTAssertEqual(result, .unavailable)
        XCTAssertEqual(result.displayText, "无法对齐（章节缺失）")
    }

    /// **按位置匹配度降序排序**（FR-018：多副本并存按匹配度降序）。
    func testCandidatesRankedByMatchScoreDescending() {
        let list = [candidate("a", score: 0.3),
                    candidate("b", score: 0.99),
                    candidate("c", score: 0.62)]
        XCTAssertEqual(VersionAlignmentEngine.ranked(list).map(\.id), ["b", "c", "a"])
    }

    /// 版本标签默认「未命名版本」，**我方不预设任何值**。
    func testDefaultVersionLabel() {
        let c = candidate("a", score: 0.5)
        XCTAssertEqual(c.versionLabel, "未命名版本")
        XCTAssertEqual(VersionCandidate.defaultVersionLabel, "未命名版本")
    }

    /// 字段：格式·大小 与 匹配度展示。
    func testDisplayFields() {
        let c = VersionCandidate(id: "a", fileName: "红楼梦.txt", fileSizeBytes: 2_200_000,
                                 format: "TXT", matchScore: 0.999)
        XCTAssertEqual(c.formatAndSize, "TXT · 2.1 MB")
        XCTAssertEqual(c.matchText, "精确")

        let partial = candidate("b", score: 0.62)
        XCTAssertEqual(partial.matchText, "62%")
    }

    /// 标题归一（去空白与标点）用于指纹匹配。
    func testTitleNormalize() {
        XCTAssertEqual(VersionAlignmentEngine.normalize("第 一 章：开头！"), "第一章开头")
    }
}
