import XCTest
@testable import InkSightAppKit

/// FR-018 版本对比（逐章指纹比较）契约测试。
final class VersionDiffTests: XCTestCase {

    /// 内容相同（含空白/标点差异）→ 一致（归一化后比较）。
    func testIdenticalAfterNormalization() {
        let report = VersionDiff.compare(
            left:  ["第一段文字。", "第二段"],
            right: ["第一 段 文字", "第二段！"]
        )
        XCTAssertEqual(report.chapters.map(\.state), [.identical, .identical],
                       "空白/标点差异应视为一致（归一化后比较）")
        XCTAssertFalse(report.hasDifferences)
    }

    /// 内容不同 → 有差异。
    func testDifferentContent() {
        let report = VersionDiff.compare(
            left:  ["原文内容", "第二章"],
            right: ["改写内容", "第二章"]
        )
        XCTAssertEqual(report.chapters[0].state, .different)
        XCTAssertEqual(report.chapters[1].state, .identical)
        XCTAssertTrue(report.hasDifferences)
    }

    /// 仅一侧存在的章（章数不同）。
    func testOneSidedChapters() {
        let report = VersionDiff.compare(
            left:  ["a", "b", "c"],
            right: ["a"]
        )
        XCTAssertEqual(report.chapters.map(\.state), [.identical, .leftOnly, .leftOnly],
                       "章数不同时多出的章标为仅一侧")

        let reverse = VersionDiff.compare(left: ["a"], right: ["a", "b"])
        XCTAssertEqual(reverse.chapters.map(\.state), [.identical, .rightOnly])
    }

    /// 汇总文案包含各状态计数。
    func testSummaryText() {
        let report = VersionDiff.compare(left: ["a", "b"], right: ["a", "x"])
        let summary = report.summary
        XCTAssertTrue(summary.contains("共 2 章"))
        XCTAssertTrue(summary.contains("一致 1"))
        XCTAssertTrue(summary.contains("有差异 1"))
    }

    /// 两侧都空 → 空报告，无差异。
    func testEmptyBothSides() {
        let report = VersionDiff.compare(left: [], right: [])
        XCTAssertTrue(report.chapters.isEmpty)
        XCTAssertFalse(report.hasDifferences)
    }

    /// 状态文案（面板展示用；不含禁词）。
    func testStateDisplayTexts() {
        XCTAssertEqual(VersionDiff.ChapterState.identical.displayText, "一致")
        XCTAssertEqual(VersionDiff.ChapterState.different.displayText, "有差异")
        XCTAssertEqual(VersionDiff.ChapterState.leftOnly.displayText, "仅当前版本")
        XCTAssertEqual(VersionDiff.ChapterState.rightOnly.displayText, "仅候选版本")
        // 禁词检查
        for state in [VersionDiff.ChapterState.identical, .different, .leftOnly, .rightOnly] {
            for banned in ["全本", "全集", "完结版", "补全", "完整版", "精校"] {
                XCTAssertFalse(state.displayText.contains(banned), "状态文案不得含禁词 \(banned)")
            }
        }
    }
}
