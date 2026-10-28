import XCTest
@testable import InkSightAppUI
import Foundation

/// FR-023 墨量统计与分享卡契约测试。
final class InkMetricsContractTests: XCTestCase {

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

    /// 墨量页展示**四项统计**（时长/本数/连续天/时段分布）。
    func testInkScreenShowsFourMetrics() throws {
        let src = try source("PlaceholderScreens.swift")
        XCTAssertTrue(src.contains("累计阅读"), "须展示累计时长")
        XCTAssertTrue(src.contains("读过"), "须展示本数")
        XCTAssertTrue(src.contains("连续阅读"), "须展示连续天")
        XCTAssertTrue(src.contains("时段分布"), "须展示时段分布")
    }

    /// **诚实空态**：无记录时显示「尚未记录」，不伪造 0。
    func testEmptyStateIsHonest() throws {
        let src = try source("PlaceholderScreens.swift")
        XCTAssertTrue(src.contains("尚未记录"), "无数据须诚实显示「尚未记录」而非 0")
    }

    /// 分享卡**用配色生成**，不使用第三方书封图。
    func testShareCardUsesGradientNotThirdPartyCover() throws {
        let src = try source("ShareCardView.swift")
        XCTAssertTrue(src.contains("LinearGradient"), "卡面须用配色渐变生成")
        // 不得引用第三方书封图/网络图片
        XCTAssertFalse(src.contains("AsyncImage"), "不得加载第三方书封图")
        XCTAssertFalse(src.contains("coverImageData"), "分享卡不使用书封数据")
    }

    /// 阅读器退出时上报会话时长（FR-023 数据来源）。
    func testReaderReportsSessionDuration() throws {
        let src = try source("ReaderSurface.swift")
        XCTAssertTrue(src.contains("recordReadingSessionIfPossible"),
                      "退出阅读器须上报阅读时长")
        XCTAssertTrue(src.contains("sessionStart"), "须记录阅读开始时刻")
    }

    /// 上报有噪声抑制（<1 分钟不计）。
    func testSessionReportingSuppressesNoise() throws {
        let src = try source("ReaderSurface.swift")
        guard let range = src.range(of: "private func recordReadingSessionIfPossible") else {
            return XCTFail("找不到上报方法")
        }
        let body = String(src[range.lowerBound...].prefix(500))
        XCTAssertTrue(body.contains("minutes >= 1"), "不足 1 分钟不应计入")
    }

    /// 时段分布展示四档（晨/午/晚/夜）。
    func testTimeSlotsDisplayed() throws {
        let src = try source("PlaceholderScreens.swift")
        XCTAssertTrue(src.contains("TimeSlot.allCases"), "须遍历时段展示分布")
    }
}
