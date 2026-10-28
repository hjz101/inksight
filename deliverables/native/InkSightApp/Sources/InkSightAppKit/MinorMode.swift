import Foundation
import InkSightCore

// MARK: - GuardianVerification（FR-032 ③ 监护验证码）

/// 监护验证（FR-032 ③：`.minorConfirmed` **不可自行退出**，需监护验证码）。
///
/// 设计要点：
/// - 验证码**不存明文**——只存加盐哈希（本项目无网络、无服务端，故这是"不落明文"的底线）；
/// - 校验失败计入尝试次数，超限锁定（防止孩子暴力试）；
/// - **验证码本身不落日志**（与 FR-034 凭据纪律同源：只记类别与结果，不记内容）。
public final class GuardianVerification: @unchecked Sendable {

    /// 校验结果（不含验证码内容）。
    public enum Result: Equatable, Sendable {
        case success
        case wrongCode
        case lockedOut(remainingSeconds: Int)
        case notConfigured
    }

    /// 最大失败次数（超出即临时锁定）。
    public static let maxAttempts = 5
    /// 锁定时长（秒）。
    public static let lockoutSeconds = 60

    private let lock = NSLock()
    private var codeHash: UInt64?          // 加盐哈希（无明文）
    private var salt: UInt64 = 0
    private var failedAttempts = 0
    private var lockedUntil: Date?

    public init() {}

    /// 是否已配置验证码。
    public var isConfigured: Bool {
        lock.lock(); defer { lock.unlock() }
        return codeHash != nil
    }

    /// 设置验证码（首次由家长设定；`Set` 会把明文哈希后丢弃）。
    public func setCode(_ code: String, salt: UInt64 = 0x9E3779B97F4A7C15) {
        lock.lock(); defer { lock.unlock() }
        self.salt = salt
        self.codeHash = Self.hash(code, salt: salt)
        self.failedAttempts = 0
        self.lockedUntil = nil
    }

    /// 校验验证码。
    public func verify(_ code: String, now: Date = Date()) -> Result {
        lock.lock()
        let hash = codeHash
        let until = lockedUntil
        if let until, until > now {
            let remaining = Int(until.timeIntervalSince(now).rounded(.up))
            lock.unlock()
            return .lockedOut(remainingSeconds: max(0, remaining))
        }
        guard let stored = hash else {
            lock.unlock()
            return .notConfigured
        }
        if Self.hash(code, salt: salt) == stored {
            failedAttempts = 0
            lockedUntil = nil
            lock.unlock()
            return .success
        }
        failedAttempts += 1
        if failedAttempts >= GuardianVerification.maxAttempts {
            failedAttempts = 0
            lockedUntil = now.addingTimeInterval(TimeInterval(GuardianVerification.lockoutSeconds))
            let remaining = GuardianVerification.lockoutSeconds
            lock.unlock()
            return .lockedOut(remainingSeconds: remaining)
        }
        lock.unlock()
        return .wrongCode
    }

    /// 加盐哈希（FNV-1a 64，复用领域内既有指纹实现的口径；**不存明文**）。
    private static func hash(_ code: String, salt: UInt64) -> UInt64 {
        Fingerprint.fnv1a64(code) ^ salt
    }
}

// MARK: - 家长内容确认（FR-032 ④）

/// 家长内容确认结果（进入未成年人模式时对书架的选择）。
///
/// - `全部保留` / `仅保留指定`；
/// - 家长侧**隐藏清单**：孩子不可见、不可撤销。
public struct ParentalContentDecision: Codable, Equatable, Sendable {
    /// 是否全部保留（false ＝ 仅保留 `keptBookIDs`）。
    public var keepAll: Bool
    /// 保留的书（`keepAll == false` 时生效）。
    public var keptBookIDs: Set<String>
    /// 家长隐藏清单（孩子不可见、不可撤销——**只能由家长验证后修改**）。
    public var hiddenBookIDs: Set<String>

    public init(keepAll: Bool = true,
                keptBookIDs: Set<String> = [],
                hiddenBookIDs: Set<String> = []) {
        self.keepAll = keepAll
        self.keptBookIDs = keptBookIDs
        self.hiddenBookIDs = hiddenBookIDs
    }

    /// 孩子侧可见的书（应用隐藏清单与保留选择）。
    public func visibleBooks(from all: [String]) -> [String] {
        all.filter { id in
            if hiddenBookIDs.contains(id) { return false }   // 隐藏优先
            return keepAll || keptBookIDs.contains(id)
        }
    }
}

// MARK: - 模式内进度隔离与合并（FR-032 ⑥）

/// 未成年人模式内的进度隔离与退出合并（FR-032 ⑥）。
///
/// 契约（原文）：
/// - 模式内进度**独立存储**；
/// - 经监护验证正常退出时**自动合并回主进度**；
/// - 沿用 FR-025「**时间戳为准、两份都保留**」，**不弹选择框**；
/// - 白名单仅「阅读位置／书签／笔记」。
public enum MinorModeProgressMerger {

    /// 合并结果（供测试与观测）。
    public struct MergeReport: Equatable, Sendable {
        /// 采用模式内进度的书（模式内更新）。
        public let tookMinorProgress: [String]
        /// 保留主进度的书（主进度更新）。
        public let keptMainProgress: [String]

        public init(tookMinorProgress: [String], keptMainProgress: [String]) {
            self.tookMinorProgress = tookMinorProgress
            self.keptMainProgress = keptMainProgress
        }
    }

    /// 带时间戳的进度条目（合并需要时间戳；`ReadingProgress` 本身不含时间戳，
    /// 故用包装类型承载——**不修改冻结的 ReadingProgress 契约**）。
    public struct StampedProgress: Equatable, Sendable {
        public let progress: ReadingProgress
        public let timestamp: Date

        public init(progress: ReadingProgress, timestamp: Date) {
            self.progress = progress
            self.timestamp = timestamp
        }
    }

    /// 合并：**时间戳为准，两份都保留**（按 bookID 各自取较新者），不弹选择框。
    ///
    /// - Returns: 合并后的进度表与报告。
    public static func merge(main: [StampedProgress],
                             minor: [StampedProgress]) -> (merged: [StampedProgress], report: MergeReport) {
        var byBook: [String: StampedProgress] = [:]
        var tookMinor: [String] = []
        var keptMain: [String] = []

        for entry in main {
            byBook[entry.progress.bookID] = entry
            keptMain.append(entry.progress.bookID)
        }
        for entry in minor {
            let id = entry.progress.bookID
            if let existing = byBook[id] {
                // 时间戳为准：模式内更新则覆盖
                if entry.timestamp > existing.timestamp {
                    byBook[id] = entry
                    tookMinor.append(id)
                    keptMain.removeAll { $0 == id }
                }
                // 两份都保留：同一 bookID 的旧条目被较新者取代，但书本身不丢
            } else {
                byBook[id] = entry
                tookMinor.append(id)
            }
        }
        return (Array(byBook.values), MergeReport(tookMinorProgress: tookMinor.sorted(),
                                                  keptMainProgress: keptMain.sorted()))
    }
}
