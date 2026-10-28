import Foundation

// MARK: - ShakeRateLimiter（EGG5 摇一摇限流）

/// 摇一摇限流器（EGG5：3 次/分）。
///
/// **纪律（designer 规范原文）**：摇动的**注册**与限流是**同一条开关**——
/// 动效关闭（`dropTrigger`）时限流器**一并停跑**，**不得分别修改**。
///
/// 「一并停跑」的准确含义：
/// 1. 摇动**不响应**（面板不出现）；
/// 2. **不消耗限流额度**——否则用户关掉动效期间会「白扣次数」，
///    重新打开动效后第一次摇就被限流挡掉，这是不可接受的行为。
public final class ShakeRateLimiter: @unchecked Sendable {

    /// 每分钟允许的触发次数（默认 3）。
    public let limitPerMinute: Int

    private var timestamps: [Date] = []
    private var running = true
    private let lock = NSLock()

    public init(limitPerMinute: Int = 3) {
        self.limitPerMinute = max(1, limitPerMinute)
    }

    /// 限流器是否在跑（＝摇动是否已注册）。
    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }

    /// 随触发注册一同开关（动效总关／单关 → 停跑）。
    ///
    /// 停跑时**清空已消耗额度**：关闭期间的旧额度不应影响重新打开后的行为。
    public func setRunning(_ running: Bool) {
        lock.lock(); defer { lock.unlock() }
        self.running = running
        if !running { timestamps.removeAll() }
    }

    /// 摇动是否放行。
    ///
    /// - 停跑 → 一律**不放行**，且**不消耗额度**；
    /// - 在跑 → 按 `limitPerMinute` 限流（滚动窗口 60 秒）。
    public func allowsTrigger(now: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard running else { return false }
        timestamps.removeAll { now.timeIntervalSince($0) >= 60 }
        guard timestamps.count < limitPerMinute else { return false }
        timestamps.append(now)
        return true
    }

    /// 已消耗的额度（观测用）。
    public var consumedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return timestamps.count
    }

    /// 清空额度（会话结束／切书）。
    public func reset() {
        lock.lock(); defer { lock.unlock() }
        timestamps.removeAll()
    }
}
