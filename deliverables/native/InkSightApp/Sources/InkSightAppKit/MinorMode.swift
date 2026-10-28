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
    /// 加盐迭代哈希凭证（**无明文**）；nil ＝ 未配置。
    private var credential: GuardianCredential?
    private var failedAttempts = 0
    private var lockedUntil: Date?
    /// 凭证落盘仓库（FR-032：重启后仍可验证）。
    private let store: GuardianCredentialStore

    /// - Parameter store: 凭证仓库；默认落盘（重启后验证码仍有效）。
    ///   单测可传临时路径隔离。
    public init(store: GuardianCredentialStore = GuardianCredentialStore()) {
        self.store = store
        self.credential = store.load()
    }

    /// 是否已配置验证码（含**磁盘上已配置**的情形）。
    public var isConfigured: Bool {
        lock.lock(); defer { lock.unlock() }
        return credential != nil
    }

    /// 设置验证码（首次由家长设定；**明文立即哈希后丢弃，只落盘加盐摘要**）。
    public func setCode(_ code: String,
                        iterations: Int = GuardianCredential.defaultIterations) throws {
        let cred = GuardianCredential.make(code: code, iterations: iterations)
        lock.lock()
        self.credential = cred
        self.failedAttempts = 0
        self.lockedUntil = nil
        lock.unlock()
        try store.save(cred)
    }

    /// 校验并签发凭据（FR-032 ④：修改隐藏清单须家长在场）。
    ///
    /// 与 `verify` 同一判定逻辑，成功时额外返回 **`GuardianProof`**——
    /// 该凭据只能由本方法签发（构造器 internal），外部无法伪造。
    public func verifyForProof(_ code: String, now: Date = Date()) -> GuardianProof? {
        verify(code, now: now) == .success ? GuardianProof(issuedAt: now) : nil
    }

    /// 校验验证码。
    public func verify(_ code: String, now: Date = Date()) -> Result {
        lock.lock()
        let cred = credential
        let until = lockedUntil
        if let until, until > now {
            let remaining = Int(until.timeIntervalSince(now).rounded(.up))
            lock.unlock()
            return .lockedOut(remainingSeconds: max(0, remaining))
        }
        guard let stored = cred else {
            lock.unlock()
            return .notConfigured
        }
        if stored.matches(code: code) {
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
}


// MARK: - GuardianProof（监护验证凭据）

/// 监护验证通过凭据（FR-032 ④：修改隐藏清单须家长在场）。
///
/// **只能由 `GuardianVerification.verify` 在成功时签发**——构造器为 internal，
/// 外部模块无法伪造凭据。这是"需监护验证"从文案变成**类型约束**的关键。
public struct GuardianProof: Sendable {
    /// 签发时间（可用于时效判断）。
    public let issuedAt: Date
    /// 有效期（秒）：默认 5 分钟，够完成一次设置操作。
    public static let validitySeconds: TimeInterval = 300

    internal init(issuedAt: Date = Date()) {
        self.issuedAt = issuedAt
    }

    /// 凭据是否仍在有效期内。
    public var isValid: Bool {
        Date().timeIntervalSince(issuedAt) <= GuardianProof.validitySeconds
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
    /// 家长隐藏清单（孩子不可见、不可撤销）。
    ///
    /// **`private(set)`：只能经 `setHidden(_:hidden:authorizedBy:)` 修改**——
    /// FR-032 ④「隐藏清单需家长验证后修改」由**类型层强制**，不是文案约定。
    public private(set) var hiddenBookIDs: Set<String>

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

    /// 修改隐藏清单 —— **必须携带已通过的监护验证凭据**。
    ///
    /// FR-032 ④：隐藏清单「孩子不可见、不可撤销」。撤销/修改须家长在场：
    /// 本方法要求传入 **`.success` 的验证事件**，否则拒绝修改并返回 false。
    ///
    /// - Parameters:
    ///   - bookID: 目标书。
    ///   - hidden: true ＝ 隐藏；false ＝ 取消隐藏（同样需凭证——「不可撤销」指孩子不能撤）。
    ///   - authorizedBy: 监护验证凭据（由 `GuardianVerification.verify` 成功后签发）。
    /// - Returns: 是否实际修改（无凭据或校验失败返回 false）。
    @discardableResult
    public mutating func setHidden(_ bookID: String, hidden: Bool,
                                   authorizedBy proof: GuardianProof?) -> Bool {
        guard let proof, proof.isValid else { return false }
        if hidden { hiddenBookIDs.insert(bookID) }
        else { hiddenBookIDs.remove(bookID) }
        return true
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
    public struct StampedProgress: Codable, Equatable, Sendable {
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

// MARK: - MinorModeProgressStore（FR-032 ⑥ 模式内独立存储）

/// 未成年人模式内的进度**独立存储**（与主进度互不污染）。
///
/// 用途：模式内阅读写这里；**经监护验证正常退出时**调 `MinorModeExitCoordinator.exit`
/// 合并回主进度（时间戳为准、两份都保留、不弹选择框）。
public final class MinorModeProgressStore: @unchecked Sendable {

    private var entries: [String: MinorModeProgressMerger.StampedProgress] = [:]
    private let lock = NSLock()

    public static let defaultDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("com.inksight/minormode", isDirectory: true)
    }()

    public static let defaultFileName = "MinorModeProgress.json"

    public let fileURL: URL

    public init(fileURL: URL = defaultDirectory.appendingPathComponent(defaultFileName)) {
        self.fileURL = fileURL
        try? load()
    }

    /// 记录模式内进度（带时间戳）。
    public func record(_ progress: ReadingProgress, at timestamp: Date = Date()) throws {
        lock.lock()
        entries[progress.bookID] = MinorModeProgressMerger.StampedProgress(
            progress: progress, timestamp: timestamp)
        let snapshot = Array(entries.values)
        lock.unlock()
        try persist(snapshot)
    }

    /// 全部模式内进度。
    public func all() -> [MinorModeProgressMerger.StampedProgress] {
        lock.lock(); defer { lock.unlock() }
        return Array(entries.values)
    }

    /// 清空（合并完成后调用）。
    public func clear() throws {
        lock.lock()
        entries.removeAll()
        lock.unlock()
        try persist([])
    }

    private func persist(_ snapshot: [MinorModeProgressMerger.StampedProgress]) throws {
        let data = try JSONEncoder().encode(snapshot)
        try Persist.write(data, to: fileURL, payload: .readingProgress,
                          excludedFromBackup: false).get()
    }

    private func load() throws {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(
                [MinorModeProgressMerger.StampedProgress].self, from: data) else { return }
        lock.lock(); defer { lock.unlock() }
        entries = Dictionary(uniqueKeysWithValues: decoded.map { ($0.progress.bookID, $0) })
    }
}

// MARK: - MinorModeExitCoordinator（FR-032 ⑥ 退出合并）

/// 模式退出协调器：**经监护验证正常退出时自动合并**模式内进度回主进度。
///
/// 契约（FR-032 ⑥）：
/// - 只在**验证通过**后合并（未通过不合并、保留模式内数据供下次）；
/// - 合并规则沿用 `MinorModeProgressMerger`（时间戳为准、两份都保留、**不弹选择框**）；
/// - 合并成功后清空模式内存储（已归位，不留第二份真相）。
public enum MinorModeExitCoordinator {

    /// 退出结果。
    public struct ExitOutcome: Equatable, Sendable {
        public let merged: Bool
        public let report: MinorModeProgressMerger.MergeReport?
    }

    /// 尝试退出未成年人模式。
    ///
    /// - Parameters:
    ///   - code: 家长输入的监护验证码。
    ///   - verification: 验证器（含磁盘凭证）。
    ///   - minorStore: 模式内进度存储。
    ///   - mainStore: 主进度仓库（合并目标）。
    ///   - now: 当前时间（测试可注入）。
    /// - Returns: 是否合并成功。
    @discardableResult
    public static func exit(code: String,
                            verification: GuardianVerification,
                            minorStore: MinorModeProgressStore,
                            mainStore: ReadingProgressStore,
                            now: Date = Date()) throws -> ExitOutcome {
        guard verification.verify(code, now: now) == .success else {
            return ExitOutcome(merged: false, report: nil)   // 未通过：不合并、保留数据
        }

        // **主进度没有时间戳字段**（`ReadingProgress` 是冻结的 4 字段契约），
        // 故无法与模式内条目做真实时间戳比较。
        // 取舍（保守方向）：**模式内条目胜出**——它来自刚结束的这次会话，比"上次停在哪"
        // 更可能是用户想要的落点；用 `distantPast` 表示"主进度无时间戳信息"，
        // 避免用 `now` 造成"主进度永远更新"的错误覆盖。
        let mainStamped = mainStore.allProgress().map {
            MinorModeProgressMerger.StampedProgress(progress: $0, timestamp: .distantPast)
        }
        let minor = minorStore.all()
        let (mergedList, report) = MinorModeProgressMerger.merge(main: mainStamped, minor: minor)

        for entry in mergedList {
            mainStore.record(entry.progress)
        }
        try minorStore.clear()   // 已归位，清空模式内副本
        return ExitOutcome(merged: true, report: report)
    }
}
