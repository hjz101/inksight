import XCTest
@testable import InkSightAppUI
import Foundation

/// FR-023 阅读轨迹切换点契约测试（PRD 的克制要求逐条）。
final class TrajectoryDotTests: XCTestCase {

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

    /// 常量对齐 PRD：**6pt 点**、**12pt 合并阈值**。
    func testConstantsMatchSpec() {
        XCTAssertEqual(TrajectoryDotView.diameter, 6, "PRD：6pt 中性圆点")
        XCTAssertEqual(TrajectoryDotView.mergeThreshold, 12, "PRD：间距 <12pt 合并")
    }

    /// **间距 <12pt 合并**为一个点，count 记录次数。
    func testMergeWithinThreshold() {
        // 0, 5, 10 三点两两间距 <12 → 合并成 1 个点（count=3）
        let merged = TrajectoryMerge.merge([0, 5, 10])
        XCTAssertEqual(merged.count, 1, "间距 <12pt 应合并为一点")
        XCTAssertEqual(merged[0].count, 3, "应记录合并次数")
        XCTAssertEqual(merged[0].position, 5, accuracy: 0.01, "位置取组内均值")
    }

    /// 间距 ≥12pt 不合并。
    func testNoMergeBeyondThreshold() {
        let merged = TrajectoryMerge.merge([0, 20, 40])
        XCTAssertEqual(merged.count, 3, "间距 ≥12pt 不应合并")
        XCTAssertTrue(merged.allSatisfy { $0.count == 1 })
    }

    /// 空输入 → 空输出（诚实）。
    func testEmptyInput() {
        XCTAssertTrue(TrajectoryMerge.merge([]).isEmpty)
    }

    /// 乱序输入也能正确合并（内部排序）。
    func testUnsortedInput() {
        let merged = TrajectoryMerge.merge([10, 0, 5])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].count, 3)
    }

    /// **点击只出中性说明**「此处切换过文件」。
    func testExpandedShowsNeutralExplanation() throws {
        let src = try source("TrajectoryDotView.swift")
        XCTAssertTrue(src.contains("此处切换过文件"), "须有中性说明文案")
    }

    /// **不做评价**：不得出现版本优劣/文件名对比/"找更好的"引导。
    func testNoEvaluativeLanguage() throws {
        let src = try source("TrajectoryDotView.swift")
        for banned in ["更好", "优劣", "推荐", "源的", "对比"] {
            XCTAssertFalse(src.contains("\"\(banned)"),
                           "轨迹点不得含评价性表述：\(banned)")
        }
    }

    /// **不用红/强调色**（PRD：标红是自曝）。
    ///
    /// 注意：不能用 `contains(".red")` 判——`.reduce(...)` 里也含 ".red" 子串，
    /// 会误报。用**精确的颜色构造形态**断言。
    func testUsesNeutralColorNotAccent() throws {
        let src = try source("TrajectoryDotView.swift")
        for redForm in ["Color.red", ".fill(.red)", "Color(.systemRed)"] {
            XCTAssertFalse(src.contains(redForm), "不得用红色（PRD：标红是自曝）——命中 \(redForm)")
        }
        XCTAssertFalse(src.contains("accentColor"), "不得用强调色")
        XCTAssertTrue(src.contains("Color.secondary"), "须用中性二级色（--ink-text-3 语义）")
    }

    /// **无脉冲、无角标**（省略"无"的写法：源码不得含 pulse/badge 动画）。
    func testNoPulseOrBadge() throws {
        let src = try source("TrajectoryDotView.swift")
        XCTAssertFalse(src.contains("pulse"), "无脉冲（PRD 明文）")
        XCTAssertFalse(src.contains(".badge"), "无角标（PRD 明文）")
        XCTAssertFalse(src.contains("repeatForever"), "无循环动画")
    }
}
