import XCTest
@testable import InkSightAppUI
import Foundation

/// FR-023 阅读轨迹日志契约测试。
final class TrajectoryLogTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-traj-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func makeLog() -> TrajectoryLog {
        TrajectoryLog(fileURL: tempDir.appendingPathComponent("t-\(UUID().uuidString).json"))
    }

    /// 记录切换点并按比例排序。
    func testRecordAndSort() throws {
        var log = makeLog()
        try log.recordSwitch(at: 0.7)
        try log.recordSwitch(at: 0.2)
        XCTAssertEqual(log.allPoints.map(\.progressRatio), [0.2, 0.7], "应按位置排序")
    }

    /// 比例夹取到 0…1（越界值不污染）。
    func testRatioClamped() throws {
        var log = makeLog()
        try log.recordSwitch(at: -0.5)
        try log.recordSwitch(at: 1.9)
        XCTAssertEqual(log.allPoints.map(\.progressRatio), [0, 1])
    }

    /// **结构上不含身份信息**（PRD：不显示版本优劣、不做文件名对比）。
    ///
    /// 只存 progressRatio + timestamp——连 bookID 都没有，
    /// 从类型上杜绝"被拿去比较版本"的可能。
    func testLogStructurallyCarriesNoIdentity() throws {
        var log = makeLog()
        try log.recordSwitch(at: 0.5)
        let data = try JSONEncoder().encode(log.allPoints)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let keys = Set(json[0].keys)
        for forbidden in ["bookID", "fileName", "sourceName", "versionLabel", "title"] {
            XCTAssertFalse(keys.contains(forbidden), "轨迹点不得含身份信息：\(forbidden)")
        }
        XCTAssertTrue(keys.contains("progressRatio"), "只存位置")
    }

    /// 持久化往返。
    func testPersistRoundTrip() throws {
        let url = tempDir.appendingPathComponent("p.json")
        var log = TrajectoryLog(fileURL: url)
        try log.recordSwitch(at: 0.3)
        try log.recordSwitch(at: 0.8)

        let reloaded = TrajectoryLog(fileURL: url)
        XCTAssertEqual(reloaded.allPoints.map(\.progressRatio), [0.3, 0.8])
    }

    /// 清空轨迹。
    func testClear() throws {
        var log = makeLog()
        try log.recordSwitch(at: 0.5)
        try log.clear()
        XCTAssertTrue(log.allPoints.isEmpty)
    }

    /// 渲染桥接：<12pt 的点合并（count 记录次数）。
    @MainActor
    func testRendererMergesClosePoints() throws {
        var log = makeLog()
        // 轴长 313pt：0.50 与 0.51 相距约 3.1pt < 12pt → 合并
        try log.recordSwitch(at: 0.50)
        try log.recordSwitch(at: 0.51)
        let dots = TrajectoryRenderer.dots(from: log, axisLength: 313)
        XCTAssertEqual(dots.count, 1, "近邻点应合并")
        XCTAssertEqual(dots[0].count, 2)
    }

    /// 渲染桥接：远离的点不合并。
    @MainActor
    func testRendererKeepsDistantPointsSeparate() throws {
        var log = makeLog()
        try log.recordSwitch(at: 0.2)   // 313*0.2 = 62.6
        try log.recordSwitch(at: 0.8)   // 313*0.8 = 250.4（相距 188pt）
        let dots = TrajectoryRenderer.dots(from: log, axisLength: 313)
        XCTAssertEqual(dots.count, 2)
    }

    /// 阅读器在切换版本时记录轨迹点。
    func testReaderRecordsOnVersionSwitch() throws {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/InkSightAppUI/ReaderSurface.swift")
        let src = try String(contentsOf: base, encoding: .utf8)
        XCTAssertTrue(src.contains("TrajectoryLog()"), "切换版本须记录轨迹")
        XCTAssertTrue(src.contains("recordSwitch(at:"), "须调用记录方法")
    }
}
