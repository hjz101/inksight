import XCTest
@testable import InkSightAppKit
import InkSightCore

/// FR-032 ③④⑥ 契约测试。
final class MinorModeTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-guardian-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    /// 隔离的验证器（凭证落临时目录，避免污染真实 Application Support）。
    private func makeVerifier() -> GuardianVerification {
        GuardianVerification(store: GuardianCredentialStore(
            fileURL: tempDir.appendingPathComponent("g-\(UUID().uuidString).json")))
    }

    // MARK: - ③ 监护验证码

    /// 未配置时返回 notConfigured（不默认放行）。
    func testNotConfigured() {
        let v = makeVerifier()
        XCTAssertFalse(v.isConfigured)
        XCTAssertEqual(v.verify("1234"), .notConfigured)
    }

    /// 正确验证码 → success；错误 → wrongCode。
    func testVerifyCorrectAndWrong() throws {
        let v = makeVerifier()
        try v.setCode("1234")
        XCTAssertTrue(v.isConfigured)
        XCTAssertEqual(v.verify("1234"), .success)
        XCTAssertEqual(v.verify("0000"), .wrongCode)
    }

    /// **不存明文**：验证码只以加盐哈希存在（无法从对象里读出明文）。
    func testCodeIsNotStoredInPlaintext() throws {
        let v = makeVerifier()
        try v.setCode("mySecretCode")
        // 遍历镜像属性，确认没有任何 String 字段等于明文
        let mirror = Mirror(reflecting: v)
        for child in mirror.children {
            if let s = child.value as? String {
                XCTAssertNotEqual(s, "mySecretCode", "不得以明文保存验证码")
            }
        }
        // 哈希后仍能校验成功（说明存的是派生值）
        XCTAssertEqual(v.verify("mySecretCode"), .success)
    }

    /// 超出最大失败次数 → 锁定（防暴力尝试）。
    func testLockoutAfterMaxAttempts() throws {
        let v = makeVerifier()
        try v.setCode("1234")
        for _ in 0..<(GuardianVerification.maxAttempts - 1) {
            XCTAssertEqual(v.verify("0000"), .wrongCode)
        }
        // 第 maxAttempts 次失败 → 锁定
        guard case .lockedOut(let remaining) = v.verify("0000") else {
            return XCTFail("达到最大失败次数应锁定")
        }
        XCTAssertGreaterThan(remaining, 0)
        // 锁定期间即使验证码正确也拒绝
        guard case .lockedOut = v.verify("1234") else {
            return XCTFail("锁定期间应保持锁定，即使输入正确")
        }
    }

    /// 锁定到期后可再次验证。
    func testLockoutExpires() throws {
        let v = makeVerifier()
        try v.setCode("1234")
        let now = Date()
        for _ in 0..<GuardianVerification.maxAttempts { _ = v.verify("0000", now: now) }
        let later = now.addingTimeInterval(TimeInterval(GuardianVerification.lockoutSeconds) + 1)
        XCTAssertEqual(v.verify("1234", now: later), .success, "锁定到期后应可验证")
    }

    // MARK: - ④ 家长内容确认

    /// 全部保留（默认）。
    func testKeepAll() {
        let d = ParentalContentDecision(keepAll: true)
        XCTAssertEqual(d.visibleBooks(from: ["a", "b", "c"]), ["a", "b", "c"])
    }

    /// 仅保留指定。
    func testKeepOnlySelected() {
        let d = ParentalContentDecision(keepAll: false, keptBookIDs: ["b"])
        XCTAssertEqual(d.visibleBooks(from: ["a", "b", "c"]), ["b"])
    }

    /// **隐藏清单优先**（孩子不可见）。
    func testHiddenOverridesKeep() {
        let d = ParentalContentDecision(keepAll: true, hiddenBookIDs: ["c"])
        XCTAssertEqual(d.visibleBooks(from: ["a", "b", "c"]), ["a", "b"],
                       "隐藏清单优先于「全部保留」")
    }

    // MARK: - ⑥ 模式内进度独立存储与合并

    private func progress(_ bookID: String, offset: Int) -> ReadingProgress {
        ReadingProgress(bookID: bookID, chapterID: 0, charOffset: offset, fingerprint: 1)
    }

    /// **时间戳为准**：模式内更新的书采用模式内进度，其余保留主进度。
    func testMergeTakesNewerByTimestamp() {
        let t0 = Date(timeIntervalSince1970: 1000)
        let t1 = Date(timeIntervalSince1970: 2000)
        let main = [MinorModeProgressMerger.StampedProgress(progress: progress("a", offset: 10), timestamp: t0),
                    MinorModeProgressMerger.StampedProgress(progress: progress("b", offset: 20), timestamp: t0)]
        let minor = [MinorModeProgressMerger.StampedProgress(progress: progress("a", offset: 99), timestamp: t1)]

        let (merged, report) = MinorModeProgressMerger.merge(main: main, minor: minor)
        let byBook = Dictionary(uniqueKeysWithValues: merged.map { ($0.progress.bookID, $0.progress.charOffset) })
        XCTAssertEqual(byBook["a"], 99, "模式内更新（时间戳更新）应采用模式内进度")
        XCTAssertEqual(byBook["b"], 20, "主进度未被动过应保留")
        XCTAssertEqual(report.tookMinorProgress, ["a"])
        XCTAssertEqual(report.keptMainProgress, ["b"])
    }

    /// 主进度更新时保留主进度（不被旧模式内进度覆盖）。
    func testMergeKeepsMainWhenMainIsNewer() {
        let t0 = Date(timeIntervalSince1970: 1000)
        let t1 = Date(timeIntervalSince1970: 2000)
        let main = [MinorModeProgressMerger.StampedProgress(progress: progress("a", offset: 50), timestamp: t1)]
        let minor = [MinorModeProgressMerger.StampedProgress(progress: progress("a", offset: 10), timestamp: t0)]

        let (merged, report) = MinorModeProgressMerger.merge(main: main, minor: minor)
        XCTAssertEqual(merged.first?.progress.charOffset, 50, "主进度更新时应保留主进度")
        XCTAssertTrue(report.tookMinorProgress.isEmpty)
    }

    /// **两份都保留**（书本身不丢——模式内独有的书也合并进来）。
    func testMergeKeepsBothSidesBooks() {
        let t = Date(timeIntervalSince1970: 1000)
        let main = [MinorModeProgressMerger.StampedProgress(progress: progress("a", offset: 1), timestamp: t)]
        let minor = [MinorModeProgressMerger.StampedProgress(progress: progress("z", offset: 2), timestamp: t)]

        let (merged, _) = MinorModeProgressMerger.merge(main: main, minor: minor)
        XCTAssertEqual(Set(merged.map(\.progress.bookID)), ["a", "z"], "两份的书都要保留")
    }

    /// 合并结果是 `ReadingProgress`（**无 pageIndex**，定位铁律不因合并而破）。
    func testMergeOutputHasNoPageIndex() throws {
        let t = Date()
        let main = [MinorModeProgressMerger.StampedProgress(progress: progress("a", offset: 1), timestamp: t)]
        let (merged, _) = MinorModeProgressMerger.merge(main: main, minor: [])
        let data = try JSONEncoder().encode(merged.map(\.progress))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertFalse(json[0].keys.contains("pageIndex"), "合并结果仍不得含 pageIndex")
    }
}
