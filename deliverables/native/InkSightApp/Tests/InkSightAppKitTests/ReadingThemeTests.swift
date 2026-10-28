import XCTest
@testable import InkSightAppKit

/// FR-010 夜间与主题契约测试（依 DESIGN §1.1 / §3）。
final class ReadingThemeTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-theme-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    /// **夜航两档制**（DESIGN §1.1：不设第三档）。
    func testNightContrastHasExactlyTwoTiers() {
        XCTAssertEqual(NightContrast.allCases.count, 2, "两档制，不设第三档")
        XCTAssertEqual(NightContrast.standard.textHex, "#8A8A8A")
        XCTAssertEqual(NightContrast.highContrast.textHex, "#CFCDC7")
        // AC：≥4.5:1（20pt 属 WCAG 大字）
        XCTAssertGreaterThanOrEqual(NightContrast.standard.contrastRatio, 4.5,
                                    "默认档 5.4:1 必须满足 4.5:1 门槛")
        XCTAssertGreaterThanOrEqual(NightContrast.highContrast.contrastRatio, 4.5)
        XCTAssertGreaterThan(NightContrast.highContrast.contrastRatio,
                             NightContrast.standard.contrastRatio)
    }

    /// 夜航底色 #121212；雪纸为近白纸面。
    func testSkinBackgrounds() {
        XCTAssertEqual(ThemeSkin.nightVoyage.paperBackgroundHex, "#121212")
        XCTAssertEqual(ThemeSkin.snowPaper.paperBackgroundHex, "#FCFCFB")
    }

    /// 正文色随皮肤切换：雪纸深色字，夜航按对比档。
    func testTextColorFollowsSkin() {
        var state = ThemeState(skin: .snowPaper)
        XCTAssertEqual(state.textHex, "#1A1A1C", "雪纸用深色字")

        state.skin = .nightVoyage
        state.nightContrast = .standard
        XCTAssertEqual(state.textHex, "#8A8A8A")

        state.nightContrast = .highContrast
        XCTAssertEqual(state.textHex, "#CFCDC7")
    }

    /// 夜间时段边界：22:00–6:00（含 22 不含 6）。
    func testNightHourBoundary() {
        XCTAssertTrue(ThemeState.isNightHour(22))
        XCTAssertTrue(ThemeState.isNightHour(23))
        XCTAssertTrue(ThemeState.isNightHour(0))
        XCTAssertTrue(ThemeState.isNightHour(5))
        XCTAssertFalse(ThemeState.isNightHour(6), "6 点不是夜间")
        XCTAssertFalse(ThemeState.isNightHour(12))
        XCTAssertFalse(ThemeState.isNightHour(21))
    }

    /// 按时段模式：夜间切夜航，白天雪纸。
    func testByTimeSwitchesSkin() {
        let state = ThemeState(mode: .byTime)
        XCTAssertEqual(state.effectiveSkin(hour: 23), .nightVoyage, "夜间应切夜航")
        XCTAssertEqual(state.effectiveSkin(hour: 3), .nightVoyage)
        XCTAssertEqual(state.effectiveSkin(hour: 14), .snowPaper, "白天应回雪纸")
    }

    /// 手动模式：用户选择优先，不随时段变。
    func testManualModeOverridesTime() {
        let state = ThemeState(skin: .snowPaper, mode: .manual)
        XCTAssertEqual(state.effectiveSkin(hour: 23), .snowPaper,
                       "手动选雪纸，夜间也保持雪纸")
    }

    /// 环境光模式本机退化为按时段（诚实降级，不伪装传感器）。
    func testAmbientLightDegradesToTime() {
        let state = ThemeState(mode: .byAmbientLight)
        XCTAssertEqual(state.effectiveSkin(hour: 23), .nightVoyage)
        XCTAssertEqual(state.effectiveSkin(hour: 14), .snowPaper)
    }

    /// 持久化往返。
    func testThemeStoreRoundTrip() throws {
        let store = ThemeStore(fileURL: tempDir.appendingPathComponent("t.json"))
        let state = ThemeState(skin: .nightVoyage, nightContrast: .highContrast, mode: .manual)
        try store.save(state)
        XCTAssertEqual(ThemeStore(fileURL: store.fileURL).load(), state)
    }

    /// 无文件时默认（按时段 + 雪纸 + 标准对比）。
    func testThemeStoreDefaultWhenNoFile() {
        let store = ThemeStore(fileURL: tempDir.appendingPathComponent("missing.json"))
        XCTAssertEqual(store.load(), ThemeState())
    }
}
