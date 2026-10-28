import XCTest
@testable import InkSightAppKit

/// FR-023 墨量统计引擎契约测试。
final class ReadingMetricsTests: XCTestCase {

    private var calendar: Calendar!
    private var metrics: ReadingMetrics!

    override func setUp() {
        // 固定时区，避免测试因系统时区漂移
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar = cal
        metrics = ReadingMetrics(calendar: cal)
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
