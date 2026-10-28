import Foundation

// MARK: - GuardianSession（FR-032 ③④ 跨页面共享的监护会话）

/// 监护会话：**跨页面共享**的验证器与已签发凭据。
///
/// 解决的问题（D-85 遗留）：
/// - 此前 `guardianProof` 是单个视图的 `@State`——换页面即失效，用户要反复验证；
/// - 此前 `GuardianVerification` 挂在 `@State` 上（引用类型），视图重建时会重新
///   `init()` 并从磁盘重载，**失败计数与锁定状态会被意外重置**（安全隐患：反复重建
///   视图即可绕过 5 次锁定）。
///
/// 本类型是 `ObservableObject` 单例：**构造保证唯一**（NFR-13 同源纪律），
/// 状态变更可被多个视图订阅。
@MainActor
public final class GuardianSession: ObservableObject {

    /// App 级单例（构造保证）。
    public static let shared = GuardianSession()

    @Published public private(set) var proof: GuardianProof?
    public let verification: GuardianVerification

    /// - Parameter verification: 验证器；默认落盘到 Application Support。
    public init(verification: GuardianVerification = GuardianVerification()) {
        self.verification = verification
    }

    /// 凭据是否有效（未过期）。
    public var hasValidProof: Bool {
        guard let proof else { return false }
        return proof.isValid
    }

    /// 校验验证码；成功则签发并**共享**凭据（5 分钟有效）。
    @discardableResult
    public func verifyAndAuthorize(_ code: String, now: Date = Date()) -> GuardianProof? {
        guard let issued = verification.verifyForProof(code, now: now) else { return nil }
        proof = issued
        return issued
    }

    /// 当前凭据（过期则返回 nil 并清除）。
    public func currentProof(now: Date = Date()) -> GuardianProof? {
        guard let proof else { return nil }
        guard now.timeIntervalSince(proof.issuedAt) <= GuardianProof.validitySeconds else {
            self.proof = nil
            return nil
        }
        return proof
    }

    /// 主动失效（离开监护设置页时可调；默认不清，让 5 分钟自然过期）。
    public func invalidate() {
        proof = nil
    }
}
