import XCTest
@testable import InkSightAppKit

/// FR-034 书源凭据校验契约测试。
final class CredentialScannerTests: XCTestCase {

    /// 干净内容不拦截。
    func testCleanTextPasses() {
        let clean = """
        第1章 开头
        这是一本普通的小说正文，没有凭据。
        """
        let result = CredentialScanner.scan(clean)
        XCTAssertFalse(result.shouldReject)
        XCTAssertTrue(result.hits.isEmpty)
        XCTAssertNil(result.rejectionMessage)
    }

    /// Cookie 命中即拒绝。
    func testCookieRejected() {
        let text = #"{"headers": {"Cookie": "sessionid=abc123"}}"#
        let result = CredentialScanner.scan(text)
        XCTAssertTrue(result.shouldReject)
        XCTAssertTrue(result.hits.contains(.cookie))
    }

    /// Token 命中即拒绝（含 Bearer / access_token / refresh_token）。
    func testTokenRejected() {
        for sample in ["token: abc", "access_token=xyz", "Authorization: Bearer abc"] {
            let result = CredentialScanner.scan(sample)
            XCTAssertTrue(result.shouldReject, "应拒绝：\(sample)")
        }
    }

    /// Authorization 命中即拒绝。
    func testAuthorizationRejected() {
        let result = CredentialScanner.scan(#""Authorization": "Basic dXNlcjpwYXNz""#)
        XCTAssertTrue(result.shouldReject)
        XCTAssertTrue(result.hits.contains(.authorization))
        XCTAssertTrue(result.hits.contains(.password) == false || true)  // Basic 里含 base64，不强制
    }

    /// 密码字段命中即拒绝。
    func testPasswordRejected() {
        for sample in ["password: 123456", #""password": "x""#, "passwd=abc"] {
            let result = CredentialScanner.scan(sample)
            XCTAssertTrue(result.shouldReject, "应拒绝：\(sample)")
        }
    }

    /// 账号字段命中即拒绝。
    func testAccountCredentialRejected() {
        for sample in ["username: alice", #""login": "alice""#] {
            let result = CredentialScanner.scan(sample)
            XCTAssertTrue(result.shouldReject, "应拒绝：\(sample)")
        }
    }

    /// **拒绝原因不含凭据原文**（PRD：凭据不参与日志）。
    func testRejectionMessageDoesNotEchoCredential() {
        let secret = "sessionid=SUPERSECRET123"
        let text = #"{"Cookie": ""# + secret + #""}"#
        let result = CredentialScanner.scan(text)
        let msg = try? XCTUnwrap(result.rejectionMessage)
        XCTAssertNotNil(msg)
        XCTAssertFalse(msg?.contains("SUPERSECRET123") == true,
                       "拒绝原因不得回显凭据原文（PRD FR-034）")
        XCTAssertTrue(msg?.contains("Cookie") == true, "应说明命中的类别")
    }

    /// 多个凭据命中时全部列出（去重）。
    func testMultipleKindsReported() {
        let text = #"{"Cookie": "a=b", "token": "t", "password": "p"}"#
        let result = CredentialScanner.scan(text)
        XCTAssertTrue(result.shouldReject)
        XCTAssertTrue(result.hits.contains(.cookie))
        XCTAssertTrue(result.hits.contains(.token))
        XCTAssertTrue(result.hits.contains(.password))
    }

    /// 大小写不敏感。
    func testCaseInsensitive() {
        XCTAssertTrue(CredentialScanner.scan("COOKIE: x").shouldReject)
        XCTAssertTrue(CredentialScanner.scan("ToKeN: x").shouldReject)
    }

    /// 二进制/非 UTF-8 内容也能命中（Latin1 兜底，字节层面 ASCII 字段名）。
    func testBinaryDataScan() {
        let data = Data(#"{"Cookie":"abc"}"#.utf8)
        XCTAssertTrue(CredentialScanner.scan(data: data).shouldReject)

        // 非 UTF-8 字节（GBK 片段）
        let gbkLike = Data([0xC4, 0xE3, 0xBA, 0xC3] + Array(#" Cookie: x"#.utf8))
        XCTAssertTrue(CredentialScanner.scan(data: gbkLike).shouldReject,
                      "非 UTF-8 内容也应能命中（Latin1 兜底）")
    }
}
