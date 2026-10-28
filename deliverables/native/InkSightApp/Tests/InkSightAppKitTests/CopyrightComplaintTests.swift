import XCTest
@testable import InkSightAppKit

/// FR-033 版权投诉通道契约测试。
final class CopyrightComplaintTests: XCTestCase {

    /// 齐备材料通过校验。
    func testCompleteComplaintPasses() {
        let c = CopyrightComplaint(rightsHolder: "某出版社",
                                   proofOfOwnership: "著作权登记证书扫描件",
                                   infringingURL: "https://example.com/novel/chapter-3",
                                   goodFaithStatement: "本人为著作权人，特此声明。")
        XCTAssertTrue(c.validationErrors.isEmpty, "齐备材料应通过：\(c.validationErrors)")
    }

    /// 缺一项即报缺失。
    func testMissingFieldsReported() {
        let c = CopyrightComplaint(rightsHolder: "",
                                   proofOfOwnership: "",
                                   infringingURL: "",
                                   goodFaithStatement: "")
        XCTAssertEqual(c.validationErrors.count, 4, "四项全缺应报 4 条")
    }

    /// **拒绝受理**：URL 不是 http(s) 开头（原型：拒绝无具体定位的概括主张）。
    func testNonURLInfringementRejected() {
        let c = CopyrightComplaint(rightsHolder: "A",
                                   proofOfOwnership: "B",
                                   infringingURL: "整本全篇侵权",   // 概括性主张，拒绝
                                   goodFaithStatement: "C")
        XCTAssertTrue(c.validationErrors.contains { $0.contains("http") },
                      "非 URL 的概括主张必须拒绝（拒绝无具体段落定位的主张）")
    }

    /// 处置承诺时限（原型口径：48h 回执 / 15 工作日）。
    func testDispositionCommitments() {
        XCTAssertEqual(CopyrightComplaint.acknowledgmentHours, 48)
        XCTAssertEqual(CopyrightComplaint.resolutionWorkdays, 15)
        XCTAssertEqual(CopyrightComplaint.repeatInfringementThreshold, 3)
        XCTAssertEqual(CopyrightComplaint.contactEmail, "[TBD-CONTACT]",
                       "邮箱为占位；发行前必须替换（发布闸门 A9/A10）")
    }
}
