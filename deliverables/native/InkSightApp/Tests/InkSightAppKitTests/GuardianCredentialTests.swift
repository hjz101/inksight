import XCTest
@testable import InkSightAppKit

/// FR-032 ③ 监护凭证持久化与强度契约测试。
final class GuardianCredentialTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-cred-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    /// **凭证里没有明文**：序列化后不含验证码文本。
    func testCredentialHasNoPlaintext() throws {
        let code = "MySecret1234"
        let cred = GuardianCredential.make(code: code)
        let data = try JSONEncoder().encode(cred)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains(code), "凭证文件不得含明文验证码")
        // 结构上只有 salt/digest/iterations 三个键
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(obj.keys), ["saltHex", "digestHex", "iterations"])
    }

    /// 相同码 + 相同盐 → 相同摘要（确定性）；不同码 → 不同摘要。
    func testDeterministicDerivation() {
        let salt = GuardianCredential.randomSaltHex()
        let a1 = GuardianCredential.make(code: "1234", saltHex: salt)
        let a2 = GuardianCredential.make(code: "1234", saltHex: salt)
        XCTAssertEqual(a1.digestHex, a2.digestHex)
        XCTAssertTrue(a1.matches(code: "1234"))

        let b = GuardianCredential.make(code: "1235", saltHex: salt)
        XCTAssertNotEqual(a1.digestHex, b.digestHex)
        XCTAssertFalse(a1.matches(code: "1235"))
    }

    /// **盐随机**：同一码两次生成不同盐 → 不同摘要（防彩虹表）。
    func testSaltIsRandom() {
        let a = GuardianCredential.make(code: "1234")
        let b = GuardianCredential.make(code: "1234")
        XCTAssertNotEqual(a.saltHex, b.saltHex, "两次生成应使用不同随机盐")
        XCTAssertNotEqual(a.digestHex, b.digestHex, "不同盐应产出不同摘要")
        // 但两者都能校验通过自己的码
        XCTAssertTrue(a.matches(code: "1234"))
        XCTAssertTrue(b.matches(code: "1234"))
    }

    /// 迭代次数写入凭证（便于将来升级强度）。
    func testIterationsRecorded() {
        let cred = GuardianCredential.make(code: "1", iterations: 1000)
        XCTAssertEqual(cred.iterations, 1000)
        XCTAssertEqual(GuardianCredential.defaultIterations, 100_000)
    }

    /// 常量时间比较：长度不等的输入也返回 false（不崩、不提前返回错误结果）。
    func testConstantTimeEqualHandlesLengthMismatch() {
        XCTAssertFalse(GuardianCredential.constantTimeEqual("abc", "abcd"))
        XCTAssertTrue(GuardianCredential.constantTimeEqual("abc", "abc"))
        XCTAssertFalse(GuardianCredential.constantTimeEqual("abc", "abd"))
    }

    /// **重启后仍可验证**（凭证落盘，新实例可读）。
    func testCredentialPersistsAcrossInstances() throws {
        let url = tempDir.appendingPathComponent("g.json")
        let store = GuardianCredentialStore(fileURL: url)

        let first = GuardianVerification(store: store)
        try first.setCode("2468", iterations: 1000)
        XCTAssertTrue(first.isConfigured)
        XCTAssertEqual(first.verify("2468"), .success)

        // 模拟重启：新实例从磁盘加载凭证
        let second = GuardianVerification(store: GuardianCredentialStore(fileURL: url))
        XCTAssertTrue(second.isConfigured, "重启后应仍处于已配置状态")
        XCTAssertEqual(second.verify("2468"), .success, "重启后验证码应仍然有效")
        XCTAssertEqual(second.verify("0000"), .wrongCode)
    }

    /// 未落盘时新实例 → 未配置（**不伪造已配置**）。
    func testFreshStoreIsNotConfigured() {
        let url = tempDir.appendingPathComponent("empty.json")
        let v = GuardianVerification(store: GuardianCredentialStore(fileURL: url))
        XCTAssertFalse(v.isConfigured)
        XCTAssertEqual(v.verify("1234"), .notConfigured)
    }

    /// 清除凭证后回到未配置态。
    func testClearResetsConfiguration() throws {
        let url = tempDir.appendingPathComponent("g2.json")
        let store = GuardianCredentialStore(fileURL: url)
        let v = GuardianVerification(store: store)
        try v.setCode("1357", iterations: 1000)
        try store.clear()
        let reloaded = GuardianVerification(store: GuardianCredentialStore(fileURL: url))
        XCTAssertFalse(reloaded.isConfigured, "清除后应为未配置")
    }
}
