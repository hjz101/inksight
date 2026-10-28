import Foundation
import SwiftUI

// MARK: - ReadingMetricsModel（FR-023 UI 订阅包装）

/// 墨量统计的 UI 可订阅包装（`ObservableObject`，App 级单例）。
///
/// 数据源：`ReadingMetrics`（引擎）；本类型只做「引擎 + 书架本数 → 可观察 Summary」。
@MainActor
public final class ReadingMetricsModel: ObservableObject {

    /// App 级单例（构造保证）。
    public static let shared = ReadingMetricsModel()

    /// 统计引擎（纯逻辑，可注入测试）。
    public let engine: ReadingMetrics
    /// 书架（取真实本数；nil ＝ 无书架 → 本数 0 的诚实空态）。
    public var bookShelf: BookShelfStore?

    /// 统计结果（公开读，UI 订阅变化；引擎与书架保持内部）。
    @Published public private(set) var summary: ReadingMetrics.Summary

    public init(engine: ReadingMetrics = ReadingMetrics(), bookShelf: BookShelfStore? = nil) {
        self.engine = engine
        self.bookShelf = bookShelf
        self.summary = engine.summary(bookCount: 0)
    }

    /// 刷新统计（书架/会话变化后调用）。
    public func refresh() {
        summary = engine.summary(bookCount: bookShelf?.items.count ?? 0)
    }

    /// 上报一次阅读会话并刷新。
    public func recordReading(bookID: String, minutes: Double, date: Date = Date()) {
        engine.recordReading(bookID: bookID, minutes: minutes, date: date)
        refresh()
    }

    /// 分享卡文本（配色由 UI 生成；这里给数据行）。
    public func shareLines() -> [String] {
        let s = summary
        var lines: [String] = []
        if let total = s.totalMinutes {
            lines.append("累计阅读 \(Int(total)) 分钟")
        }
        lines.append("读过 \(s.bookCount) 本书")
        if s.streakDays > 0 {
            lines.append("连续阅读 \(s.streakDays) 天")
        }
        for slot in ReadingMetrics.TimeSlot.allCases {
            if let minutes = s.distribution[slot], minutes > 0 {
                lines.append("\(slot.displayName) \(Int(minutes)) 分钟")
            }
        }
        return lines
    }
}
