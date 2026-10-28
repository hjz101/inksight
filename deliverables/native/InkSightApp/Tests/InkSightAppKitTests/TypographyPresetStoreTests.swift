import XCTest
import InkSightAppKit
import InkSightCore

/// 开发包 #6 契约测试：排版预设持久化（单门 JSON，原子写，可备份，8 字段无 pageIndex）。
final class TypographyPresetStoreTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-preset-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tmpDir { try? FileManager.default.removeItem(at: tmpDir) }
        super.tearDown()
    }

    private func presetFile() -> URL {
        tmpDir.appendingPathComponent("TypographyPreset.json")
    }

    /// round-trip：save 后 load 得到等价预设（8 字段无损）。
    func testSaveThenLoadRoundTrips() throws {
        let store = TypographyPresetStore(fileURL: presetFile())
        // D-72：改用**合法档位**（FR-009 档位制后，非法值会在落盘/读取时被归一化，
        // 旧用例的 1.6/10/6/32 会被 snap，故改为合法值验证真正的往返语义）。
        let preset = ReaderTypography(
            fontID: "PingFangSC-Regular",
            fontSize: 20,
            lineHeightMultiplier: 1.75,
            paragraphSpacingBefore: 12,
            paragraphSpacingAfter: 0,
            insets: ReaderInsets(top: 20, leading: 16, bottom: 20, trailing: 16),
            indent: 40,
            imagePlaceholderAspect: 1.4
        )
        try store.save(preset)
        let loaded = store.load()
        XCTAssertEqual(loaded, preset)
    }

    /// **越界预设在落盘/读取时被归一化**（FR-009）：旧滑块写出的非法值不得继续生效。
    func testOutOfRangePresetIsNormalizedOnSave() throws {
        let store = TypographyPresetStore(fileURL: presetFile())
        let illegal = ReaderTypography(
            fontID: "PingFangSC-Regular",
            fontSize: 14,                 // 非法 → 19
            lineHeightMultiplier: 1.2,    // 非法 → 1.70
            paragraphSpacingBefore: 8,    // → 固定 12
            paragraphSpacingAfter: 8,     // → 固定 0
            insets: ReaderInsets(top: 20, leading: 8, bottom: 20, trailing: 8),  // 8 → 16
            indent: 28,                   // 非法 → 0
            imagePlaceholderAspect: 1.4
        )
        try store.save(illegal)
        let loaded = store.load()
        XCTAssertEqual(loaded.fontSize, 19, "越界字号必须被压回合法档")
        XCTAssertEqual(loaded.lineHeightMultiplier, 1.70)
        XCTAssertEqual(loaded.paragraphSpacingBefore, 12)
        XCTAssertEqual(loaded.insets.leading, 16)
    }

    /// 无文件时返回 `.default`（诚实回退，不抛错、不伪造）。
    func testLoadWithNoFileReturnsDefault() throws {
        let store = TypographyPresetStore(fileURL: presetFile())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
        XCTAssertEqual(store.load(), ReaderTypography.default)
    }

    /// Codable 只 8 个顶层字段，无 pageIndex、无正文（定位铁律同源）。
    func testCodableHasExactlyEightFields() throws {
        let data = try JSONEncoder().encode(ReaderTypography.default)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let expected: Set<String> = [
            "fontID", "fontSize", "lineHeightMultiplier",
            "paragraphSpacingBefore", "paragraphSpacingAfter",
            "insets", "indent", "imagePlaceholderAspect",
        ]
        XCTAssertEqual(Set(obj.keys), expected, "排版预设 Codable 顶层必须恰好 8 字段")
    }

    /// 不设 `NSURLIsExcludedFromBackupKey`：落盘后文件不应被标记为「排除备份」（用户偏好应可备份）。
    func testSavedFileIsNotExcludedFromBackup() throws {
        let store = TypographyPresetStore(fileURL: presetFile())
        try store.save(ReaderTypography.default)
        let values = try store.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertNotEqual(values.isExcludedFromBackup, true,
                          "排版预设不应排除备份——用户偏好应可备份（与 SQLiteCache 8MB 硬闸相反）")
    }

    /// 默认目录落在 `Application Support/com.inksight/preset`。
    func testDefaultDirectoryIsApplicationSupportComInksightPreset() {
        let expected = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.inksight/preset", isDirectory: true)
        XCTAssertEqual(TypographyPresetStore.defaultDirectory, expected)
    }
}
