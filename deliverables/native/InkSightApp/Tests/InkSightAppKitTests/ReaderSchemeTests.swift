import XCTest
@testable import InkSightAppKit
import InkSightCore

/// FR-028 阅读方案（玻璃参数＋字体＋动效存为方案并分享）契约测试。
final class ReaderSchemeTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-scheme-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func makeScheme(name: String = "我的方案") -> ReaderScheme {
        var motion = MotionSettings()
        motion.globalEnabled = true
        return ReaderScheme(name: name,
                            skin: .peachSoda,
                            typography: TypographyTiers.normalize(.default),
                            motion: motion)
    }

    /// 方案含三部分：玻璃参数（skin）／字体（typography）／动效（motion）。
    func testSchemeContainsThreeParts() {
        let s = makeScheme()
        XCTAssertEqual(s.skin, .peachSoda, "玻璃参数")
        XCTAssertEqual(s.typography.fontSize, TypographyTiers.defaultFontSize, "字体/排版")
        XCTAssertNotNil(s.motion, "动效")
    }

    /// 空名回落「未命名方案」（**我方不预设任何值**）。
    func testEmptyNameFallback() {
        XCTAssertEqual(makeScheme(name: "").displayName, "未命名方案")
        XCTAssertEqual(makeScheme(name: "   ").displayName, "未命名方案")
        XCTAssertEqual(ReaderScheme.defaultDisplayName, "未命名方案")
    }

    /// 编码 → 解码往返一致。
    func testEncodeDecodeRoundTrip() throws {
        let original = makeScheme()
        let encoded = try ReaderSchemeCodec.encode(original)
        let decoded = try ReaderSchemeCodec.decode(encoded)
        XCTAssertEqual(decoded.skin, original.skin)
        XCTAssertEqual(decoded.typography, original.typography)
        XCTAssertEqual(decoded.motion, original.motion)
        XCTAssertEqual(decoded.displayName, original.displayName)
    }

    /// 分享形态是**可读 JSON**（不是二进制 —— 用户能检查拷给别人的是什么）。
    func testShareFormIsReadableJSON() throws {
        let encoded = try ReaderSchemeCodec.encode(makeScheme())
        XCTAssertTrue(encoded.contains("\"skin\""), "应含 skin 键")
        XCTAssertTrue(encoded.contains("\"typography\""), "应含 typography 键")
        XCTAssertTrue(encoded.contains("\"motion\""), "应含 motion 键")
        XCTAssertTrue(encoded.hasPrefix("{"), "应为 JSON 对象")
    }

    /// **不含正文/凭据**（FR-025 同源纪律）。
    func testSchemeContainsNoBookContent() throws {
        let encoded = try ReaderSchemeCodec.encode(makeScheme())
        for banned in ["chapterText", "正文", "password", "token", "Cookie"] {
            XCTAssertFalse(encoded.contains(banned), "方案不得含：\(banned)")
        }
    }

    /// 格式错误抛出明确原因（**不静默回落**）。
    func testMalformedThrows() {
        XCTAssertThrowsError(try ReaderSchemeCodec.decode("not json")) { error in
            guard let e = error as? ReaderSchemeError else {
                return XCTFail("应抛 ReaderSchemeError")
            }
            if case .malformed = e { } else { XCTFail("应为 malformed") }
            XCTAssertNotNil(e.errorDescription, "须有可读原因")
        }
    }

    /// 版本不支持时明确报错（不假装成功）。
    func testUnsupportedVersionThrows() throws {
        // 手工构造 version: 99
        let json = """
        {"version":99,"name":"x","skin":"snowPaper",
         "typography":{"fontID":"PingFangSC-Regular","fontSize":20,"lineHeightMultiplier":1.75,
         "paragraphSpacingBefore":12,"paragraphSpacingAfter":0,
         "insets":{"top":24,"leading":20,"bottom":28,"trailing":20},
         "indent":0,"imagePlaceholderAspect":0.75},
         "motion":{"globalEnabled":true,"perID":{}},"createdAt":"2026-01-01T00:00:00Z"}
        """
        XCTAssertThrowsError(try ReaderSchemeCodec.decode(json)) { error in
            guard case .unsupportedVersion(let v)? = error as? ReaderSchemeError else {
                return XCTFail("应为 unsupportedVersion")
            }
            XCTAssertEqual(v, 99)
        }
    }

    /// 本地方案仓库：保存后可列出，同名覆盖。
    func testStoreSaveAndOverwrite() throws {
        let store = ReaderSchemeStore(fileURL: tempDir.appendingPathComponent("s.json"))
        try store.save(makeScheme(name: "方案A"))
        XCTAssertEqual(store.all().count, 1)

        // 同名覆盖（不产生两个同名方案）
        var updated = makeScheme(name: "方案A")
        updated.skin = .nightVoyage
        try store.save(updated)
        XCTAssertEqual(store.all().count, 1, "同名应覆盖")
        XCTAssertEqual(store.all()[0].skin, .nightVoyage)
    }

    /// 方案持久化跨实例（重启后仍在）。
    func testStorePersists() throws {
        let url = tempDir.appendingPathComponent("s2.json")
        let store = ReaderSchemeStore(fileURL: url)
        try store.save(makeScheme(name: "持久方案"))

        let reloaded = ReaderSchemeStore(fileURL: url)
        XCTAssertEqual(reloaded.all().count, 1)
        XCTAssertEqual(reloaded.all()[0].displayName, "持久方案")
    }

    /// 删除方案。
    func testStoreRemove() throws {
        let store = ReaderSchemeStore(fileURL: tempDir.appendingPathComponent("s3.json"))
        try store.save(makeScheme(name: "待删"))
        try store.remove(named: "待删")
        XCTAssertTrue(store.all().isEmpty)
    }
}
