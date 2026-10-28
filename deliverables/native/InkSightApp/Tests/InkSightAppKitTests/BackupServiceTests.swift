import XCTest
@testable import InkSightAppKit
import InkSightCore

/// FR-025 备份导出契约测试。
final class BackupServiceTests: XCTestCase {

    private var tempDir: URL!
    private var progressStore: ReadingProgressStore!
    private var typographyStore: TypographyPresetStore!
    private var motionStore: MotionSettingsStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        progressStore = ReadingProgressStore()
        typographyStore = TypographyPresetStore(fileURL: tempDir.appendingPathComponent("typography.json"))
        motionStore = MotionSettingsStore(fileURL: tempDir.appendingPathComponent("motion.json"))
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    /// **P0 前置：落盘格式必须带 `version` 字段**（PRD FR-025 原文）。
    func testBackupPayloadHasVersionField() throws {
        let payload = BackupPayload(progress: [], typography: nil, motion: nil)
        let data = try payload.encode()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, BackupPayload.currentVersion,
                       "备份 JSON 顶层必须带 version 字段（P0 前置，老数据可迁移）")
    }

    /// **结构上无正文字段**：备份 JSON 键只能是 version/progress/typography/motion
    /// （JSONEncoder 对 nil 可选字段省略键，故分别断言「nil 时无正文键」与「有值时键集正确」）。
    func testBackupHasNoBodyTextFields() throws {
        // nil 偏好时：只有 version + progress，且绝无正文字段
        let empty = BackupPayload(progress: [], typography: nil, motion: nil)
        let emptyData = try empty.encode()
        let emptyJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: emptyData) as? [String: Any])
        let emptyKeys = Set(emptyJSON.keys)
        XCTAssertTrue(emptyKeys.contains("version"), "必须带 version")
        XCTAssertTrue(emptyKeys.contains("progress"), "必须含 progress")
        for forbidden in ["body", "content", "chapterText", "text", "typography", "motion"] {
            XCTAssertFalse(emptyKeys.contains(forbidden), "备份不得出现 \(forbidden) 字段")
        }

        // 有值时：键集精确为 4 个，仍无正文字段
        let typo = ReaderTypography(fontID: "PingFangSC-Regular", fontSize: 20, lineHeightMultiplier: 1.75,
                                    paragraphSpacingBefore: 12, paragraphSpacingAfter: 0,
                                    insets: ReaderInsets(top: 24, leading: 20, bottom: 28, trailing: 20),
                                    indent: 0, imagePlaceholderAspect: 0.75)
        let full = BackupPayload(progress: [], typography: typo, motion: MotionSettings())
        let fullData = try full.encode()
        let fullJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: fullData) as? [String: Any])
        XCTAssertEqual(Set(fullJSON.keys), ["version", "progress", "typography", "motion"],
                       "有值时备份键集必须恰为 4 个（含 version）")
        for forbidden in ["body", "content", "chapterText", "text"] {
            XCTAssertFalse(fullJSON.keys.contains(forbidden), "备份不得出现 \(forbidden) 字段")
        }
    }

    /// 导出 → 编码 → 解码 → 导入 往返，进度与偏好完整还原。
    func testExportImportRoundTrip() throws {
        // 造数据
        progressStore.record(ReadingProgress(bookID: "b1", chapterID: 2, charOffset: 1234, fingerprint: 0xABCD))
        progressStore.record(ReadingProgress(bookID: "b2", chapterID: 0, charOffset: 56, fingerprint: 0x1234))
        let typo = ReaderTypography(fontID: "PingFangSC-Regular", fontSize: 20, lineHeightMultiplier: 1.75,
                                    paragraphSpacingBefore: 12, paragraphSpacingAfter: 0,
                                    insets: ReaderInsets(top: 24, leading: 20, bottom: 28, trailing: 20),
                                    indent: 0, imagePlaceholderAspect: 0.75)
        try typographyStore.save(typo)
        var motion = MotionSettings()
        motion.globalEnabled = false
        try motionStore.save(motion)

        // 导出
        let service = BackupService(progressStore: progressStore,
                                    typographyStore: typographyStore,
                                    motionStore: motionStore)
        let payload = try service.export()
        XCTAssertEqual(payload.progress.count, 2)
        XCTAssertEqual(payload.typography, typo)
        XCTAssertEqual(payload.motion?.globalEnabled, false)

        // 编码解码（模拟落盘）
        let data = try payload.encode()
        let decoded = try BackupPayload.decode(data)

        // 导入到全新 store
        let p2 = ReadingProgressStore()
        let t2 = TypographyPresetStore(fileURL: tempDir.appendingPathComponent("t2.json"))
        let m2 = MotionSettingsStore(fileURL: tempDir.appendingPathComponent("m2.json"))
        let svc2 = BackupService(progressStore: p2, typographyStore: t2, motionStore: m2)
        try svc2.import(decoded)

        XCTAssertEqual(p2.progress(for: "b1")?.charOffset, 1234, "进度必须完整还原")
        XCTAssertEqual(p2.progress(for: "b2")?.charOffset, 56)
        XCTAssertEqual(t2.load(), typo, "排版偏好必须还原")
        XCTAssertEqual(m2.load().globalEnabled, false, "动效偏好必须还原")
    }

    /// 未知**更高**版本拒绝（避免把新格式读坏）。
    func testUnsupportedHigherVersionRejected() throws {
        let payload = BackupPayload(version: BackupPayload.currentVersion + 1,
                                    progress: [], typography: nil, motion: nil)
        let data = try payload.encode()
        XCTAssertThrowsError(try BackupPayload.decode(data)) { err in
            XCTAssertEqual(err as? BackupPayload.DecodeError,
                           .unsupportedVersion(BackupPayload.currentVersion + 1))
        }
    }

    /// 旧版本（更低）允许解码——按需迁移（P0 前置：老数据可迁移）。
    func testOlderVersionAllowed() throws {
        let payload = BackupPayload(version: 0, progress: [], typography: nil, motion: nil)
        let data = try payload.encode()
        XCTAssertNoThrow(try BackupPayload.decode(data), "更低版本应允许解码（老数据可迁移）")
    }
}
