import XCTest
@testable import InkSightAppKit

/// FR-032 监护会话**跨页面共享**契约测试。
@MainActor
final class GuardianSessionTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-session-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func makeSession() -> GuardianSession {
        GuardianSession(verification: GuardianVerification(store: GuardianCredentialStore(
            fileURL: tempDir.appendingPathComponent("g-\(UUID().uuidString).json"))))
    }

    /// 验证成功后凭据被会话持有（可跨页面读取）。
    func testVerifyIssuesSharedProof() throws {
        let session = makeSession()
        try session.verification.setCode("1234", iterations: 1000)
        XCTAssertFalse(session.hasValidProof, "初始无凭据")

        let proof = session.verifyAndAuthorize("1234")
        XCTAssertNotNil(proof)
        XCTAssertTrue(session.hasValidProof, "验证后会话应持有有效凭据")
        XCTAssertNotNil(session.currentProof())
    }

    /// 验证失败不签发凭据。
    func testWrongCodeIssuesNoProof() throws {
        let session = makeSession()
        try session.verification.setCode("1234", iterations: 1000)
        XCTAssertNil(session.verifyAndAuthorize("0000"))
        XCTAssertFalse(session.hasValidProof)
    }

    /// **凭据过期后 `currentProof` 返回 nil 并清除**（5 分钟有效期）。
    func testExpiredProofIsCleared() throws {
        let session = makeSession()
        try session.verification.setCode("1234", iterations: 1000)
        _ = session.verifyAndAuthorize("1234")

        // 6 分钟后
        let later = Date().addingTimeInterval(GuardianProof.validitySeconds + 60)
        XCTAssertNil(session.currentProof(now: later), "过期凭据应返回 nil")
        XCTAssertNil(session.proof, "过期凭据应被清除")
    }

    /// 有效期内跨"页面"仍可用（同一会话实例）。
    func testProofSharedAcrossCallers() throws {
        let session = makeSession()
        try session.verification.setCode("1234", iterations: 1000)
        _ = session.verifyAndAuthorize("1234")

        // 模拟另一个页面读取同一会话
        let proof = session.currentProof()
        XCTAssertNotNil(proof)

        var decision = ParentalContentDecision()
        XCTAssertTrue(decision.setHidden("b", hidden: true, authorizedBy: proof),
                      "共享凭据应能授权隐藏清单修改")
    }

    /// `invalidate` 主动失效。
    func testInvalidate() throws {
        let session = makeSession()
        try session.verification.setCode("1234", iterations: 1000)
        _ = session.verifyAndAuthorize("1234")
        session.invalidate()
        XCTAssertNil(session.proof)
        XCTAssertFalse(session.hasValidProof)
    }

    /// **锁定状态不会被"重建"绕过**：同一验证器连续失败达上限后，
    /// 即使重新读取 `hasValidProof` / 再验证也被拒绝（凭据会话不重置失败计数）。
    func testLockoutNotResettableByRequery() throws {
        let session = makeSession()
        try session.verification.setCode("1234", iterations: 1000)
        for _ in 0..<GuardianVerification.maxAttempts {
            _ = session.verifyAndAuthorize("0000")
        }
        // 锁定期间即使正确码也拒绝
        XCTAssertNil(session.verifyAndAuthorize("1234"), "锁定期间不得签发凭据")
        // 再查一次仍无效（不能靠"再问一次"重置）
        XCTAssertFalse(session.hasValidProof)
    }
}
