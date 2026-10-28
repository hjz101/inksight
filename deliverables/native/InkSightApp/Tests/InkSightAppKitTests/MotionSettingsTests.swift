import XCTest
@testable import InkSightAppKit
import Foundation

/// 开发包 #7 契约测试：动效开关持久化（单门 JSON，原子写，可备份，形状稳定无禁止字段）。
final class MotionSettingsTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-motion-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tmpDir { try? FileManager.default.removeItem(at: tmpDir) }
        super.tearDown()
    }

    private func settingsFile() -> URL {
        tmpDir.appendingPathComponent("MotionSettings.json")
    }

    /// round-trip：save 后 load 得到等价设置。
    func testSaveThenLoadRoundTrips() throws {
        let store = MotionSettingsStore(fileURL: settingsFile())
        var settings = MotionSettings.defaultAllEnabled
        settings.globalEnabled = false
        settings.perID[MotionID.t1BookOpen.rawValue] = false
        settings.perID[MotionID.egg5ShakePanel.rawValue] = false

        try store.save(settings)
        let loaded = store.load()

        XCTAssertFalse(loaded.globalEnabled)
        XCTAssertFalse(loaded.isEnabled(.t1BookOpen))
        XCTAssertFalse(loaded.isEnabled(.egg5ShakePanel))
        XCTAssertTrue(loaded.isEnabled(.t2VersionSwap), "未关闭的 ID 应仍为开启")
    }

    /// 无文件时返回**全部开启**的默认态（诚实回退，不抛错、不伪造）。
    func testLoadWithNoFileReturnsAllEnabledDefault() {
        let store = MotionSettingsStore(fileURL: settingsFile())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
        let loaded = store.load()
        XCTAssertTrue(loaded.globalEnabled)
        XCTAssertEqual(loaded.perID.count, 11)
        for id in MotionRegistry.perIDSwitchableIDs {
            XCTAssertTrue(loaded.isEnabled(id), "\(id) 默认应为开启")
        }
        XCTAssertEqual(loaded, MotionSettings.defaultAllEnabled)
    }

    /// JSON 键集断言：顶层恰好 `{globalEnabled, perID}`；`perID` 键只能是 11 个 MotionID rawValue。
    /// **无 pageIndex／无正文类字段**（定位铁律与合规同源：落盘模型不含任何内容）。
    func testCodableKeySetHasNoForbiddenFields() throws {
        let data = try JSONEncoder().encode(MotionSettings.defaultAllEnabled)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(Set(obj.keys), ["globalEnabled", "perID"], "顶层键集必须恰好是这两个")
        let perID = try XCTUnwrap(obj["perID"] as? [String: Any])
        XCTAssertEqual(Set(perID.keys), Set(MotionRegistry.perIDSwitchableIDs.map(\.rawValue)),
                       "perID 键必须恰好是 11 个可关 MotionID 的 rawValue")

        // 禁止字段（内容类 / 定位类）：任何一项出现即判不通过
        let forbidden = ["pageIndex", "page", "body", "text", "content", "chapter", "bookID", "charOffset", "fingerprint"]
        for key in obj.keys {
            XCTAssertFalse(forbidden.contains(key), "顶层不得出现禁止字段「\(key)」")
        }
        for key in perID.keys {
            XCTAssertFalse(forbidden.contains(key), "perID 不得出现禁止字段「\(key)」")
        }
    }

    /// 不设 `NSURLIsExcludedFromBackupKey`：动效开关属用户偏好，应可随备份恢复。
    func testSavedFileIsNotExcludedFromBackup() throws {
        let store = MotionSettingsStore(fileURL: settingsFile())
        try store.save(MotionSettings.defaultAllEnabled)
        let values = try store.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertNotEqual(values.isExcludedFromBackup, true,
                          "动效开关不应排除备份——用户偏好应可备份（与 SQLiteCache 8MB 硬闸相反）")
    }

    /// 默认目录落在 `Application Support/com.inksight/motion`（沿用 #6 的分目录约定）。
    func testDefaultDirectoryIsApplicationSupportComInksightMotion() {
        let expected = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.inksight/motion", isDirectory: true)
        XCTAssertEqual(MotionSettingsStore.defaultDirectory, expected)
    }

    /// 归一：缺键补「开」、多键剔除——落盘形状恒定（可 diff），且 T4／T5 永不入键。
    func testNormalizedFillsMissingAndDropsUnknownKeys() {
        var settings = MotionSettings(globalEnabled: true, perID: [:])
        settings.perID[MotionID.t1BookOpen.rawValue] = false
        settings.perID[MotionID.t4RestoreSettle.rawValue] = false   // 非法键：T4 无单独开关
        settings.perID[MotionID.t5SwitchRipple.rawValue] = false    // 非法键：T5 无单独开关

        let normalized = settings.normalized()
        XCTAssertEqual(normalized.perID.count, 11)
        XCTAssertFalse(normalized.isEnabled(.t1BookOpen), "已关闭的应保留关闭")
        XCTAssertTrue(normalized.isEnabled(.t2VersionSwap), "缺键应补为开启")
        XCTAssertNil(normalized.perID[MotionID.t4RestoreSettle.rawValue], "T4 不应有独立开关键")
        XCTAssertNil(normalized.perID[MotionID.t5SwitchRipple.rawValue], "T5 不应有独立开关键")
    }
}
