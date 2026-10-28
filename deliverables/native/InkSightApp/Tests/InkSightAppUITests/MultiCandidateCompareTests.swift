import XCTest
@testable import InkSightAppUI
import Foundation

/// FR-018 多候选对比：面板须支持**逐个候选**对比，而非只比最高匹配度那个。
final class MultiCandidateCompareTests: XCTestCase {

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

    /// `onCompare` 必须接收候选参数（能按候选对比）。
    func testOnCompareTakesCandidate() throws {
        let src = try source("VersionPickerPanel.swift")
        XCTAssertTrue(src.contains("var onCompare: (VersionCandidate) -> Void"),
                      "onCompare 须接收候选，支持多副本逐个对比")
    }

    /// 每个候选行都有独立「对比」入口。
    func testEachRowHasCompareButton() throws {
        let src = try source("VersionPickerPanel.swift")
        XCTAssertTrue(src.contains("onCompare(candidate)"),
                      "候选行须提供逐行对比入口")
        XCTAssertTrue(src.contains("Button(\"对比\")"), "须有「对比」按钮")
    }

    /// 阅读器按候选构建报告（不再写死 candidates.first）。
    func testReaderBuildsReportForGivenCandidate() throws {
        let src = try source("ReaderSurface.swift")
        XCTAssertTrue(src.contains("against candidate: VersionCandidate"),
                      "buildCompareReport 须以指定候选为参数")
        XCTAssertTrue(src.contains("buildCompareReport(for: live, against: candidate)"),
                      "调用处须传入所选候选")
        XCTAssertFalse(src.contains("candidates.first"),
                       "不得再写死只比第一个候选")
    }

    /// 对比入口无候选时应禁用（避免点开空面板）。
    func testCompareDisabledWithoutCandidates() throws {
        let src = try source("VersionPickerPanel.swift")
        XCTAssertTrue(src.contains(".disabled(candidates.isEmpty)"),
                      "无候选时对比按钮应禁用")
    }

    /// 逐候选对比**不切换版本**（对比是只读操作）。
    func testCompareDoesNotSwitchVersion() throws {
        let src = try source("VersionPickerPanel.swift")
        guard let range = src.range(of: "Button(\"对比\")") else {
            return XCTFail("找不到对比按钮")
        }
        let nearby = String(src[range.lowerBound...].prefix(200))
        XCTAssertFalse(nearby.contains("onSelect"), "对比按钮不得触发版本切换")
    }
}
