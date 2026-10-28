import XCTest
@testable import InkSightAppKit

/// FR-023 墨量统计引擎契约测试。
final class ReadingMetricsTests: XCTestCase {

    private var calendar: Calendar!
    private var metrics: ReadingMetrics!
    private var tempDir: URL!

    override func setUpWithError() throws {
        // 固定时区，避免测试因系统时区漂移
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar = cal
        // **fileURL: nil 走纯内存**，不污染真实 Application Support
        metrics = ReadingMetrics(calendar: cal, fileURL: nil)
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-metrics-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    /// 无记录 → **诚实空态**（totalMinutes nil，不伪造 0）。
    func testEmptyMetricsIsHonest() {
        let s = metrics.summary(bookCount: 3)
        XCTAssertNil(s.totalMinutes, "无记录不应伪造 0 分钟")
        XCTAssertNil(s.todayMinutes)
        XCTAssertEqual(s.streakDays, 0)
        XCTAssertTrue(s.distribution.isEmpty)
        XCTAssertEqual(s.bookCount, 3, "本数来自书架真实值")
    }

    /// 累计时长正确。
    func testTotalMinutes() {
        metrics.recordReading(bookID: "b", minutes: 10,
                              date: date("2026-10-28 08:00"))
        metrics.recordReading(bookID: "b", minutes: 20,
                              date: date("2026-10-28 09:00"))
        let s = metrics.summary(bookCount: 1)
        XCTAssertEqual(s.totalMinutes, 30)
    }

    /// 时段分布：晨/午/晚/夜归入正确槽。
    func testDistribution() {
        metrics.recordReading(bookID: "b", minutes: 10, date: date("2026-10-28 08:00"))  // 晨
        metrics.recordReading(bookID: "b", minutes: 10, date: date("2026-10-28 13:00"))  // 午
        metrics.recordReading(bookID: "b", minutes: 10, date: date("2026-10-28 19:00"))  // 晚
        metrics.recordReading(bookID: "b", minutes: 10, date: date("2026-10-28 23:00"))  // 夜
        let s = metrics.summary(bookCount: 1)
        XCTAssertEqual(s.distribution[.morning], 10)
        XCTAssertEqual(s.distribution[.afternoon], 10)
        XCTAssertEqual(s.distribution[.evening], 10)
        XCTAssertEqual(s.distribution[.night], 10)
    }

    /// 连续天：今天+昨天+前天 = 3。
    func testStreak() {
        let now = date("2026-10-28 12:00")
        metrics.recordReading(bookID: "b", minutes: 5, date: now)
        metrics.recordReading(bookID: "b", minutes: 5, date: date("2026-10-27 12:00"))
        metrics.recordReading(bookID: "b", minutes: 5, date: date("2026-10-26 12:00"))
        let s = metrics.summary(bookCount: 1, now: now)
        XCTAssertEqual(s.streakDays, 3)
    }

    /// 今天没读但昨天/前天读了 → streak = 2（从昨天开始数）。
    func testStreakCountsFromYesterdayIfTodayMissed() {
        let now = date("2026-10-28 12:00")
        metrics.recordReading(bookID: "b", minutes: 5, date: date("2026-10-27 12:00"))
        metrics.recordReading(bookID: "b", minutes: 5, date: date("2026-10-26 12:00"))
        let s = metrics.summary(bookCount: 1, now: now)
        XCTAssertEqual(s.streakDays, 2, "今天未读应从昨天起算连续天")
    }

    /// 中断（中间缺一天）→ streak 断。
    func testStreakBreaksOnGap() {
        let now = date("2026-10-28 12:00")
        metrics.recordReading(bookID: "b", minutes: 5, date: now)
        metrics.recordReading(bookID: "b", minutes: 5, date: date("2026-10-26 12:00"))  // 27 缺
        let s = metrics.summary(bookCount: 1, now: now)
        XCTAssertEqual(s.streakDays, 1, "中断后 streak 从今天重新数")
    }

    /// 今日分钟：仅今日的记录。
    func testTodayMinutes() {
        let now = date("2026-10-28 12:00")
        metrics.recordReading(bookID: "b", minutes: 30, date: now)
        metrics.recordReading(bookID: "b", minutes: 10, date: date("2026-10-27 12:00"))
        let s = metrics.summary(bookCount: 1, now: now)
        XCTAssertEqual(s.todayMinutes, 30)
        XCTAssertEqual(s.totalMinutes, 40)
    }

    /// 时段槽边界：5 点晨读、11 点午读、17 点晚读、22 点夜读。
    func testSlotBoundaries() {
        XCTAssertEqual(ReadingMetrics.TimeSlot.slot(for: 5), .morning)
        XCTAssertEqual(ReadingMetrics.TimeSlot.slot(for: 11), .afternoon)
        XCTAssertEqual(ReadingMetrics.TimeSlot.slot(for: 17), .evening)
        XCTAssertEqual(ReadingMetrics.TimeSlot.slot(for: 22), .night)
        XCTAssertEqual(ReadingMetrics.TimeSlot.slot(for: 3), .night)
    }

    /// 时段展示名（UI 用）。
    func testSlotDisplayNames() {
        XCTAssertEqual(ReadingMetrics.TimeSlot.morning.displayName, "晨读")
        XCTAssertEqual(ReadingMetrics.TimeSlot.night.displayName, "夜读")
    }

    private func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.date(from: s) ?? Date()
    }
}

/// FR-023 统计**持久化**：重启后统计仍在（D-92 记录的缺口）。
final class ReadingMetricsPersistenceTests: XCTestCase {

    private var tempDir: URL!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-metrics-p-\\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar = cal
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    /// 上报后落盘；新实例（模拟重启）能读回累计时长。
    func testSessionsPersistAcrossInstances() {
        let url = tempDir.appendingPathComponent("m.json")
        let first = ReadingMetrics(calendar: calendar, fileURL: url)
        first.recordReading(bookID: "b1", minutes: 30)
        first.recordReading(bookID: "b1", minutes: 15)

        let second = ReadingMetrics(calendar: calendar, fileURL: url)
        XCTAssertEqual(second.allSessions().count, 2, "重启后会话应仍在")
        XCTAssertEqual(second.summary(bookCount: 1).totalMinutes, 45, "累计时长应保持")
    }

    /// 无文件时为空（诚实，不伪造）。
    func testNoFileIsEmpty() {
        let url = tempDir.appendingPathComponent("missing.json")
        let m = ReadingMetrics(calendar: calendar, fileURL: url)
        XCTAssertTrue(m.allSessions().isEmpty)
        XCTAssertNil(m.summary(bookCount: 0).totalMinutes)
    }

    /// 纯内存模式（fileURL: nil）不落盘。
    func testInMemoryModeDoesNotWrite() {
        let m = ReadingMetrics(calendar: calendar, fileURL: nil)
        m.recordReading(bookID: "b", minutes: 10)
        XCTAssertEqual(m.allSessions().count, 1)
        XCTAssertEqual(m.summary(bookCount: 1).totalMinutes, 10, "内存模式统计正常")
        // 关键：内存模式不产生文件
        let files = (try? FileManager.default.contentsOfDirectory(atPath: tempDir.path)) ?? []
        XCTAssertTrue(files.isEmpty, "纯内存模式不应写文件")
    }
}
