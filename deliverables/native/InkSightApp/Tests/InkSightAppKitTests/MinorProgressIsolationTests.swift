import XCTest
@testable import InkSightAppKit
import InkSightCore

/// FR-032 ⑥ 模式内进度**写入隔离**：未成年人模式下进度只进模式内存储，不污染主进度。
final class MinorProgressIsolationTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-iso-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func progress(_ bookID: String, offset: Int) -> ReadingProgress {
        ReadingProgress(bookID: bookID, chapterID: 0, charOffset: offset, fingerprint: 7)
    }

    /// 模式内存储写入后可读回，且**主进度不受影响**（两者是不同仓库）。
    func testMinorWriteDoesNotTouchMainStore() throws {
        let minor = MinorModeProgressStore(fileURL: tempDir.appendingPathComponent("m.json"))
        let main = ReadingProgressStore()

        try main.record(progress("b1", offset: 10))       // 进入模式前的主进度
        try minor.record(progress("b1", offset: 200))     // 模式内阅读

        XCTAssertEqual(main.progress(for: "b1")?.charOffset, 10, "主进度不应被模式内写入污染")
        XCTAssertEqual(minor.all().first?.progress.charOffset, 200)
    }

    /// 模式内写入**跨实例持久化**（模拟阅读中重启）。
    func testMinorWritePersists() throws {
        let url = tempDir.appendingPathComponent("m2.json")
        let store = MinorModeProgressStore(fileURL: url)
        try store.record(progress("b", offset: 33))
        let reloaded = MinorModeProgressStore(fileURL: url)
        XCTAssertEqual(reloaded.all().first?.progress.charOffset, 33)
    }

    /// 模式内同一本书多次阅读 → 后者覆盖（带时间戳）。
    func testMinorWriteOverwritesSameBook() throws {
        let store = MinorModeProgressStore(fileURL: tempDir.appendingPathComponent("m3.json"))
        try store.record(progress("b", offset: 1), at: Date(timeIntervalSince1970: 1000))
        try store.record(progress("b", offset: 2), at: Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(store.all().count, 1, "同一本书只保留一条")
        XCTAssertEqual(store.all().first?.progress.charOffset, 2)
    }

    /// 完整闭环：模式内阅读 → 验证退出 → 合并回主进度 → 模式内清空。
    func testFullLoopReadThenExitMerges() throws {
        let minorURL = tempDir.appendingPathComponent("m4.json")
        let minor = MinorModeProgressStore(fileURL: minorURL)
        let main = ReadingProgressStore()
        let verification = GuardianVerification(store: GuardianCredentialStore(
            fileURL: tempDir.appendingPathComponent("g.json")))
        try verification.setCode("9999", iterations: 1000)

        // 主进度：上次停在 50
        try main.record(progress("book", offset: 50))
        // 模式内阅读到 500
        try minor.record(progress("book", offset: 500))

        let outcome = try MinorModeExitCoordinator.exit(
            code: "9999", verification: verification,
            minorStore: minor, mainStore: main)

        XCTAssertTrue(outcome.merged)
        XCTAssertEqual(main.progress(for: "book")?.charOffset, 500,
                       "退出后主进度应归位到模式内阅读的位置")
        XCTAssertTrue(minor.all().isEmpty, "模式内副本应清空")
    }

    /// 模式内进度的 `ReadingProgress` 仍无 pageIndex。
    func testMinorProgressHasNoPageIndex() throws {
        let store = MinorModeProgressStore(fileURL: tempDir.appendingPathComponent("m5.json"))
        try store.record(progress("b", offset: 9))
        let data = try JSONEncoder().encode(store.all())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let progressDict = try XCTUnwrap(json[0]["progress"] as? [String: Any])
        XCTAssertFalse(progressDict.keys.contains("pageIndex"))
    }
}
