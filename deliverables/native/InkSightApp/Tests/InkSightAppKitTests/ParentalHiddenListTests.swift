import XCTest
@testable import InkSightAppKit

/// FR-032 ④ 隐藏清单**类型层强制**：无监护凭据不能修改、凭据不可伪造、有效期内可用。
final class ParentalHiddenListTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-hidden-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func makeVerifier() -> GuardianVerification {
        GuardianVerification(store: GuardianCredentialStore(
            fileURL: tempDir.appendingPathComponent("g-\(UUID().uuidString).json")))
    }

    /// **无凭据不能修改隐藏清单**（setHidden 返回 false，集合不变）。
    func testNoProofCannotHide() {
        var decision = ParentalContentDecision()
        let changed = decision.setHidden("book1", hidden: true, authorizedBy: nil)
        XCTAssertFalse(changed, "无监护凭据应拒绝修改")
        XCTAssertTrue(decision.hiddenBookIDs.isEmpty, "隐藏清单不应变化")
    }

    /// **验证成功后签发凭据，可修改**。
    func testProofFromVerifyAllowsHide() throws {
        let v = makeVerifier()
        try v.setCode("1234", iterations: 1000)

        // 错误验证码 → 无凭据
        XCTAssertNil(v.verifyForProof("0000"))
        // 正确验证码 → 有凭据
        let proof = try XCTUnwrap(v.verifyForProof("1234"))

        var decision = ParentalContentDecision()
        XCTAssertTrue(decision.setHidden("book1", hidden: true, authorizedBy: proof))
        XCTAssertTrue(decision.hiddenBookIDs.contains("book1"))
    }

    /// 凭据可**取消隐藏**（同样需凭据——「不可撤销」指孩子不能撤）。
    func testProofAlsoRequiredToUnhide() throws {
        let v = makeVerifier()
        try v.setCode("1234", iterations: 1000)
        let proof = try XCTUnwrap(v.verifyForProof("1234"))

        var decision = ParentalContentDecision()
        XCTAssertTrue(decision.setHidden("b", hidden: true, authorizedBy: proof))
        XCTAssertTrue(decision.setHidden("b", hidden: false, authorizedBy: proof))
        XCTAssertFalse(decision.hiddenBookIDs.contains("b"))

        // 无凭据无法撤销
        XCTAssertTrue(decision.setHidden("b", hidden: true, authorizedBy: proof))
        XCTAssertFalse(decision.setHidden("b", hidden: false, authorizedBy: nil))
        XCTAssertTrue(decision.hiddenBookIDs.contains("b"), "无凭据不得撤销隐藏")
    }

    /// **历史凭据过期**（5 分钟）不能再用。
    func testExpiredProofIsInvalid() {
        let old = GuardianProof(issuedAt: Date().addingTimeInterval(-GuardianProof.validitySeconds - 10))
        XCTAssertFalse(old.isValid)

        var decision = ParentalContentDecision()
        XCTAssertFalse(decision.setHidden("x", hidden: true, authorizedBy: old),
                       "过期凭据应被拒绝")
        XCTAssertTrue(decision.hiddenBookIDs.isEmpty)
    }

    /// **隐藏清单优先**：即使「全部保留」，隐藏的书对孩子不可见。
    func testHiddenStillOverridesKeepAll() throws {
        let v = makeVerifier()
        try v.setCode("1234", iterations: 1000)
        let proof = try XCTUnwrap(v.verifyForProof("1234"))

        var decision = ParentalContentDecision(keepAll: true)
        XCTAssertTrue(decision.setHidden("secret", hidden: true, authorizedBy: proof))
        XCTAssertFalse(decision.visibleBooks(from: ["a", "secret", "c"]).contains("secret"))
    }

    /// 凭据有效期常量。
    func testValidityConstant() {
        XCTAssertEqual(GuardianProof.validitySeconds, 300, "凭据有效期 5 分钟")
        XCTAssertTrue(GuardianProof().isValid)
    }
}
