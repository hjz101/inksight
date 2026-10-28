import Foundation
import InkSightCore

// MARK: - ReadingMetrics（FR-023 墨量统计）

/// 阅读统计（FR-023：**时长/本数/连续天/时段分布**）。
///
/// 数据口径（诚实，不造数）：
/// - **时长**：由调用方逐会话上报（`recordReading(minutes:)`）；无数据时不伪造"0 分钟"而是 nil；
/// - **本数**：书架真实项数；
/// - **连续天**：按上报日期的连续天数（跨天即断）；
/// - **时段分布**：把上报时刻归入 4 个时段（晨/午/晚/夜）。
public final class ReadingMetrics: @unchecked Sendable {

    /// 单次阅读会话记录。
    public struct Session: Codable, Equatable, Sendable {
        public let bookID: String
        public let minutes: Double
        public let date: Date

        public init(bookID: String, minutes: Double, date: Date) {
            self.bookID = bookID
            self.minutes = minutes
            self.date = date
        }
    }

    /// 时段（FR-023 时段分布）。
    public enum TimeSlot: String, CaseIterable, Sendable {
        case morning   // 5–11
        case afternoon // 11–17
        case evening   // 17–22
        case night     // 22–5

        public var displayName: String {
            switch self {
            case .morning:   return "晨读"
            case .afternoon: return "午读"
            case .evening:   return "晚读"
            case .night:     return "夜读"
            }
        }

        /// 由小时（0–23）归入时段。
        public static func slot(for hour: Int) -> TimeSlot {
            switch hour {
            case 5..<11:  return .morning
            case 11..<17: return .afternoon
            case 17..<22: return .evening
            default:      return .night
            }
        }
    }

    /// 统计结果（供 UI 展示；无数据字段为 nil，**诚实空态**）。
    public struct Summary: Equatable, Sendable {
        /// 累计阅读分钟（nil ＝ 无上报，不伪造 0）。
        public let totalMinutes: Double?
        /// 已读本数（书架真实数）。
        public let bookCount: Int
        /// 连续阅读天数（无记录 → 0）。
        public let streakDays: Int
        /// 时段分布（分钟；无记录 → 空表）。
        public let distribution: [TimeSlot: Double]
        /// 今日阅读分钟（nil ＝ 今日未读）。
        public let todayMinutes: Double?

        public init(totalMinutes: Double?, bookCount: Int, streakDays: Int,
                    distribution: [TimeSlot: Double], todayMinutes: Double?) {
            self.totalMinutes = totalMinutes
            self.bookCount = bookCount
            self.streakDays = streakDays
            self.distribution = distribution
            self.todayMinutes = todayMinutes
        }
    }

    private var sessions: [Session] = []
    private let lock = NSLock()
    /// 日历时区（测试可注入；默认当前）。
    private var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// 上报一次阅读会话。
    public func recordReading(bookID: String, minutes: Double, date: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        sessions.append(Session(bookID: bookID, minutes: minutes, date: date))
    }

    /// 全部会话（供导出/分享）。
    public func allSessions() -> [Session] {
        lock.lock(); defer { lock.unlock() }
        return sessions
    }

    /// 统计汇总（依赖外部传入书架本数——统计引擎不持有书架，保持纯逻辑可测）。
    public func summary(bookCount: Int, now: Date = Date()) -> Summary {
        lock.lock(); defer { lock.unlock() }
        guard !sessions.isEmpty else {
            return Summary(totalMinutes: nil, bookCount: bookCount,
                           streakDays: 0, distribution: [:], todayMinutes: nil)
        }

        let total = sessions.reduce(0) { $0 + $1.minutes }
        let today = calendar.isDateInToday(now) ? now : now
        let todayMinutes = sessions
            .filter { calendar.isDate($0.date, inSameDayAs: today) }
            .reduce(0) { $0 + $1.minutes }

        // 时段分布
        var distribution: [TimeSlot: Double] = [:]
        for s in sessions {
            let hour = calendar.component(.hour, from: s.date)
            let slot = TimeSlot.slot(for: hour)
            distribution[slot, default: 0] += s.minutes
        }

        return Summary(totalMinutes: total, bookCount: bookCount,
                       streakDays: computeStreak(now: now),
                       distribution: distribution,
                       todayMinutes: todayMinutes > 0 ? todayMinutes : nil)
    }

    /// 连续阅读天数：从今天（或最近一次）向前数连续有记录的天数。
    private func computeStreak(now: Date) -> Int {
        guard !sessions.isEmpty else { return 0 }
        // 去重日期集合
        let days = Set(sessions.map { calendar.startOfDay(for: $0.date) })
        // 从今天开始向前数；今天没读则从昨天开始（streak 含"昨天至今"）
        var cursor = calendar.startOfDay(for: now)
        if !days.contains(cursor) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return streak
    }
}
