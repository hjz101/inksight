import Foundation
import CryptoKit
import InkSightCore

// MARK: - GuardianCredential（FR-032 ③ 监护验证码凭证）

/// 监护验证码凭证（**只存加盐迭代哈希，不存明文**）。
///
/// **威胁模型与强度说明（如实登记，不夸大）**：
/// - 本项目无网络、无服务端；威胁是"拿到设备的孩子随手试"；
/// - 4 位数字码只有 10⁴ 种可能，**任何本地哈希都可被穷举**——
///   故本凭证的目标是「提高尝试成本 + 配合失败锁定」，**不宣称密码学强度**；
/// - 用 **SHA-256 迭代 10 万次 + 随机盐**，远强于单次 FNV，但真正的防线是
///   `GuardianVerification` 的 5 次失败锁定；
/// - 凭证文件中**没有明文**，也没有可逆信息。
public struct GuardianCredential: Codable, Equatable, Sendable {
    /// 盐（随机 16 字节的十六进制）。
    public let saltHex: String
    /// 派生摘要（SHA-256 迭代后的十六进制）。
    public let digestHex: String
    /// 迭代次数（写入文件，便于将来升级强度）。
    public let iterations: Int

    /// 当前默认迭代次数。
    public static let defaultIterations = 100_000
    /// 盐长度（字节）。
    public static let saltLength = 16

    public init(saltHex: String, digestHex: String, iterations: Int) {
        self.saltHex = saltHex
        self.digestHex = digestHex
        self.iterations = iterations
    }

    /// 由明文码派生凭证。
    public static func make(code: String,
                            saltHex: String = GuardianCredential.randomSaltHex(),
                            iterations: Int = GuardianCredential.defaultIterations) -> GuardianCredential {
        GuardianCredential(saltHex: saltHex,
                           digestHex: derive(code: code, saltHex: saltHex, iterations: iterations),
                           iterations: iterations)
    }

    /// 校验明文码是否匹配本凭证（**常量时间比较**，避免时序侧信道）。
    public func matches(code: String) -> Bool {
        let candidate = Self.derive(code: code, saltHex: saltHex, iterations: iterations)
        return Self.constantTimeEqual(candidate, digestHex)
    }

    /// 随机盐（16 字节 → hex）。
    public static func randomSaltHex() -> String {
        var bytes = [UInt8](repeating: 0, count: saltLength)
        // 用系统随机源（CryptoKit 不直接给随机数；SystemRandomNumberGenerator 足够）
        var rng = SystemRandomNumberGenerator()
        for i in 0..<bytes.count { bytes[i] = UInt8.random(in: 0...255, using: &rng) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// 派生：`SHA256(salt ‖ code)` 迭代 `iterations` 次。
    static func derive(code: String, saltHex: String, iterations: Int) -> String {
        let salt = Data(hexString: saltHex) ?? Data()
        var data = Data()
        data.append(salt)
        data.append(Data(code.utf8))
        var digest = Data(SHA256.hash(data: data))
        guard iterations > 1 else { return digest.hexString }
        for _ in 1..<iterations {
            digest = Data(SHA256.hash(data: digest + salt))
        }
        return digest.hexString
    }

    /// 常量时间字符串比较（长度不同也走满长度，避免提前返回）。
    static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let ab = Array(a.utf8), bb = Array(b.utf8)
        var diff: UInt8 = ab.count == bb.count ? 0 : 1
        let n = max(ab.count, bb.count)
        for i in 0..<n {
            let x: UInt8 = i < ab.count ? ab[i] : 0
            let y: UInt8 = i < bb.count ? bb[i] : 0
            diff |= (x ^ y)
        }
        return diff == 0
    }
}

// MARK: - GuardianCredentialStore（凭证落盘）

/// 监护凭证仓库：经 `Persist` 门面落盘。
///
/// **备份策略**：`excludedFromBackup = false`——监护设置属用户配置，
/// 换机应可恢复（与排版/动效偏好同源语义）。
public final class GuardianCredentialStore: @unchecked Sendable {

    public static let defaultDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("com.inksight/guardian", isDirectory: true)
    }()

    public static let defaultFileName = "GuardianCredential.json"

    public let fileURL: URL

    public init(fileURL: URL = defaultDirectory.appendingPathComponent(defaultFileName)) {
        self.fileURL = fileURL
    }

    /// 读取凭证；无文件/解码失败 → nil（**不伪造已配置**）。
    public func load() -> GuardianCredential? {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(GuardianCredential.self, from: data) else {
            return nil
        }
        return decoded
    }

    public func save(_ credential: GuardianCredential) throws {
        let data = try JSONEncoder().encode(credential)
        try Persist.write(data, to: fileURL, payload: .notes, excludedFromBackup: false).get()
    }

    /// 清除（家长重设时用）。
    public func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}

// MARK: - Data/hex 辅助

extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }

    /// 由十六进制字符串构造（偶数长度才接受）。
    init?(hexString: String) {
        let chars = Array(hexString.lowercased())
        guard chars.count % 2 == 0, !chars.isEmpty else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)
        var index = 0
        while index < chars.count {
            guard let hi = chars[index].hexValue, let lo = chars[index + 1].hexValue else { return nil }
            bytes.append(hi << 4 | lo)
            index += 2
        }
        self = Data(bytes)
    }
}

private extension Character {
    /// 十六进制字符 → 0…15（非十六进制返回 nil）。
    var hexValue: UInt8? {
        guard let value = unicodeScalars.first?.value else { return nil }
        switch value {
        case 0x30...0x39: return UInt8(value - 0x30)          // '0'…'9'
        case 0x61...0x66: return UInt8(value - 0x61) + 10     // 'a'…'f'
        default: return nil
        }
    }
}
