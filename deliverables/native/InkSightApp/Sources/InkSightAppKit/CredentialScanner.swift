import Foundation
import InkSightCore

// MARK: - CredentialScanner（FR-034 书源凭据校验）

/// 凭据静态扫描（FR-034）：导入时检查待导入内容是否夹带他人的账号凭据，
/// **命中即拒绝导入并说明原因**。
///
/// 契约（PRD FR-034 原文）：
/// - 扫描 `Cookie` / `Token` / `Authorization` / 账密字段；
/// - 命中即**拒绝导入**并说明原因；
/// - 凭据**不落盘、不参与同步与日志**（本类型只做内存判定，不记录命中内容的原文）。
public enum CredentialScanner {

    /// 凭据类别（命中后告知用户"为什么被拒"，但不回显凭据本身）。
    public enum Kind: String, Sendable, CaseIterable {
        case cookie
        case token
        case authorization
        case password
        case accountCredential

        /// 用户可读说明。
        public var reason: String {
            switch self {
            case .cookie:            return "含 Cookie 字段"
            case .token:             return "含 Token 字段"
            case .authorization:     return "含 Authorization 字段"
            case .password:          return "含密码字段"
            case .accountCredential: return "含账号凭据字段"
            }
        }
    }

    /// 扫描结果。
    public struct ScanResult: Equatable, Sendable {
        /// 命中的凭据类别（去重、去序稳定）。
        public let hits: [Kind]
        /// 是否应拒绝导入。
        public var shouldReject: Bool { !hits.isEmpty }
        /// 拒绝原因（用户可读；**不含凭据原文**）。
        public var rejectionMessage: String? {
            guard shouldReject else { return nil }
            let reasons = hits.map(\.reason).joined(separator: "、")
            return "拒绝导入：\(reasons)。请移除凭据后重试（不会保存任何凭据）。"
        }
    }

    /// 扫描文本内容。
    ///
    /// 判定口径：不区分大小写匹配常见凭据字段名；**只报类别，不回显命中值**
    /// （PRD：凭据不参与日志——本方法返回的结果也不含原文）。
    public static func scan(_ text: String) -> ScanResult {
        let lower = text.lowercased()
        var hits: [Kind] = []

        if containsAny(lower, ["cookie:", "\"cookie\"", "set-cookie"]) {
            hits.append(.cookie)
        }
        if containsAny(lower, ["token:", "\"token\"", "access_token", "refresh_token", "bearer "]) {
            hits.append(.token)
        }
        if containsAny(lower, ["authorization:", "\"authorization\""]) {
            hits.append(.authorization)
        }
        if containsAny(lower, ["password:", "\"password\"", "passwd", "\"pwd\""]) {
            hits.append(.password)
        }
        if containsAny(lower, ["username:", "\"username\"", "user_account", "\"login\""]) {
            hits.append(.accountCredential)
        }
        return ScanResult(hits: hits)
    }

    /// 扫描二进制/文件字节（先按 UTF-8 解码，失败则按 Latin1 兜底以免漏检）。
    public static func scan(data: Data) -> ScanResult {
        if let text = String(data: data, encoding: .utf8) {
            return scan(text)
        }
        // 非 UTF-8 内容（如 GBK 文本）用 Latin1 近似——字节层面仍能命中 ASCII 凭据字段名
        let latin1 = String(data: data, encoding: .isoLatin1) ?? ""
        return scan(latin1)
    }

    private static func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }
}
