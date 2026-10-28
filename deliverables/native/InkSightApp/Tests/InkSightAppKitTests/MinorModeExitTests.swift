import XCTest
@testable import InkSightAppKit
import InkSightCore

/// FR-032 ⑥ 模式退出：验证通过才合并，未通过不合并且保留数据。
final class MinorModeExitTests: XCTestCase {

    private var tempDir: URL!
    private var verification: GuardianVerification!
    private var minorStore: MinorModeProgressStore!
    private var mainStore: ReadingProgressStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-exit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        verification = GuardianVerification(store: GuardianCredentialStore(
            fileURL: tempDir.appendingPathComponent("g.json")))
        minorStore = MinorModeProgressStore(fileURL: tempDir.appendingPathComponent("minor.json"))
        mainStore = ReadingProgressStore()
        try verification.setCode("1234", iterations: 1000)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func progress(_ bookID: String, offset: Int, fp: UInt64 = 1) -> ReadingProgress {
        ReadingProgress(bookID: bookID, chapterID: 0, charOffset: offset, fingerprint: fp)
    }

    /// **验证通过 → 合并并清空模式内副本**。
    func testVerifiedExitMergesAndClears() throws {
        let t0 = Date(timeIntervalSince1970: 1000)
        try mainStore.record(progress("a", offset: 10))
        try minorStore.record(progress("a", offset: 99), at: t0.addingTimeInterval(3600))

        let outcome = try MinorModeExitCoordinator.exit(
            code: "1234", verification: verification,
            minorStore: minorStore, mainStore: mainStore)

        XCTAssertTrue(outcome.merged)
        XCTAssertEqual(mainStore.progress(for: "a")?.charOffset, 99,
                       "模式内进度较新应合并进主进度")
        XCTAssertTrue(minorStore.all().isEmpty, "合并后模式内副本应清空（不留第二份真相）")
    }

    /// **验证失败 → 不合并、模式内数据保留**。
    func testWrongCodeDoesNotMerge() throws {
        try mainStore.record(progress("a", offset: 10))
        try minorStore.record(progress("a", offset: 99))

        let outcome = try MinorModeExitCoordinator.exit(
            code: "0000", verification: verification,
            minorStore: minorStore, mainStore: mainStore)

        XCTAssertFalse(outcome.merged, "验证失败不得合并")
        XCTAssertEqual(mainStore.progress(for: "a")?.charOffset, 10, "主进度不应被改动")
        XCTAssertFalse(minorStore.all().isEmpty, "模式内数据应保留供下次退出")
    }

    /// 模式内独有的书也合并进来（两份都保留）。
    func testMinorOnlyBookIsMerged() throws {
        try minorStore.record(progress("newbook", offset: 5))
        let outcome = try MinorModeExitCoordinator.exit(
            code: "1234", verification: verification,
            minorStore: minorStore, mainStore: mainStore)
        XCTAssertTrue(outcome.merged)
        XCTAssertEqual(mainStore.progress(for: "newbook")?.charOffset, 5)
    }

    /// 合并结果仍**无 pageIndex**（定位铁律不因合并破功）。
    func testMergedProgressHasNoPageIndex() throws {
        try minorStore.record(progress("a", offset: 7))
        _ = try MinorModeExitCoordinator.exit(
            code: "1234", verification: verification,
            minorStore: minorStore, mainStore: mainStore)
        let data = try mainStore.encodedJSON()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertFalse(json[0].keys.contains("pageIndex"))
    }

    /// 模式内进度**持久化跨实例**（模拟重启后仍能合并）。
    func testMinorStorePersistsAcrossInstances() throws {
        try minorStore.record(progress("x", offset: 42))
        let reloaded = MinorModeProgressStore(fileURL: minorStore.fileURL)
        XCTAssertEqual(reloaded.all().first?.progress.charOffset, 42, "模式内进度应落盘")
    }

    /// 未配置验证码 → 不能退出合并。
    func testNotConfiguredCannotExit() throws {
        let fresh = GuardianVerification(store: GuardianCredentialStore(
            fileURL: tempDir.appendingPathComponent("fresh.json")))
        try minorStore.record(progress("a", offset: 1))
        let outcome = try MinorModeExitCoordinator.exit(
            code: "anything", verification: fresh,
            minorStore: minorStore, mainStore: mainStore)
        XCTAssertFalse(outcome.merged)
        XCTAssertFalse(minorStore.all().isEmpty)
    }
}
