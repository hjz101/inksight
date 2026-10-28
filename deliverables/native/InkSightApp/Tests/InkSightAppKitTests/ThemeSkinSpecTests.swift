import XCTest
@testable import InkSightAppKit

/// FR-028 主题皮肤契约测试（DESIGN §3.1：三套做全四层，四项同时变）。
final class ThemeSkinSpecTests: XCTestCase {

    /// **三套主题齐备**（DESIGN §3.1 验收范围）。
    func testThreeSkinsExist() {
        XCTAssertEqual(ThemeSkinSpec.Skin.allCases.count, 3)
        let names = ThemeSkinSpec.Skin.allCases.map(\.displayName)
        XCTAssertTrue(names.contains("雪纸"), "须含基准主题雪纸")
        XCTAssertTrue(names.contains("夜航"), "须含暗底极值夜航")
        XCTAssertTrue(names.contains("蜜桃汽水"), "须含年轻向极值蜜桃汽水")
    }

    /// **雪纸逐值对齐** DESIGN 表格。
    func testSnowPaperExactValues() {
        let s = ThemeSkinSpec.spec(for: .snowPaper)
        XCTAssertEqual(s.iconColorHex, "#B8452F")
        XCTAssertEqual(s.iconStroke, 2)
        XCTAssertEqual(s.iconCap, .butt, "雪纸是直角端 butt")
        XCTAssertEqual(s.accentHex, "#B8452F")
        XCTAssertEqual(s.glassTintHex, "#FFFFFF")
        XCTAssertEqual(s.glassTintOpacity, 0.28, accuracy: 0.001)
        XCTAssertEqual(s.glassDispersion, 0.35, accuracy: 0.001)
        XCTAssertEqual(s.transitionFromHex, "#B8452F")
        XCTAssertEqual(s.transitionToHex, "#E8A38F")
        XCTAssertEqual(s.radiusShift, 0)
    }

    /// **夜航逐值对齐**（色散 0.20，不是 0.35）。
    func testNightVoyageExactValues() {
        let s = ThemeSkinSpec.spec(for: .nightVoyage)
        XCTAssertEqual(s.iconColorHex, "#6E8BFF")
        XCTAssertEqual(s.iconStroke, 2)
        XCTAssertEqual(s.iconCap, .round)
        XCTAssertEqual(s.accentHex, "#6E8BFF")
        XCTAssertEqual(s.glassTintHex, "#1C1C1E")
        XCTAssertEqual(s.glassTintOpacity, 0.45, accuracy: 0.001)
        XCTAssertEqual(s.glassDispersion, 0.20, accuracy: 0.001, "夜航色散是 0.20")
        XCTAssertEqual(s.transitionFromHex, "#6E8BFF")
        XCTAssertEqual(s.transitionToHex, "#3A4A80")
    }

    /// **蜜桃汽水逐值对齐**（描边 2.5pt ＋ 圆角 +4）。
    func testPeachSodaExactValues() {
        let s = ThemeSkinSpec.spec(for: .peachSoda)
        XCTAssertEqual(s.iconColorHex, "#FF6B5A")
        XCTAssertEqual(s.iconStroke, 2.5, "蜜桃汽水描边是 2.5pt")
        XCTAssertEqual(s.iconCap, .round)
        XCTAssertEqual(s.accentHex, "#FF6B5A")
        XCTAssertEqual(s.glassTintHex, "#FFD9C9")
        XCTAssertEqual(s.glassTintOpacity, 0.30, accuracy: 0.001)
        XCTAssertEqual(s.glassDispersion, 0.45, accuracy: 0.001)
        XCTAssertEqual(s.transitionFromHex, "#FF6B5A")
        XCTAssertEqual(s.transitionToHex, "#FFB3A3")
        XCTAssertEqual(s.radiusShift, 4, "蜜桃汽水全站圆角 +4")
    }

    /// **判据：换主题时四项同时变**——任一项不变即判未完成。
    func testAllFourLayersChangeAcrossSkins() {
        let skins = ThemeSkinSpec.Skin.allCases
        for i in 0..<skins.count {
            for j in (i+1)..<skins.count {
                let a = ThemeSkinSpec.spec(for: skins[i])
                let b = ThemeSkinSpec.spec(for: skins[j])
                let pair = "\(skins[i].displayName) vs \(skins[j].displayName)"

                // ① 图标（色 或 描边 或 端点，至少一项不同）
                XCTAssertTrue(a.iconColorHex != b.iconColorHex
                              || a.iconStroke != b.iconStroke
                              || a.iconCap != b.iconCap,
                              "① 图标未变：\(pair)")
                // ② 强调色
                XCTAssertNotEqual(a.accentHex, b.accentHex, "② 强调色未变：\(pair)")
                // ③ 玻璃 tint 或色散
                XCTAssertTrue(a.glassTintHex != b.glassTintHex
                              || a.glassTintOpacity != b.glassTintOpacity
                              || a.glassDispersion != b.glassDispersion,
                              "③ 玻璃未变：\(pair)")
                // ④ 转场配色
                XCTAssertTrue(a.transitionFromHex != b.transitionFromHex
                              || a.transitionToHex != b.transitionToHex,
                              "④ 转场配色未变：\(pair)")
            }
        }
    }

    /// 既有两档主题可映射到皮肤规格（向后兼容）。
    func testLegacyThemeSkinMapping() {
        let legacySnow = ThemeSkinSpec.spec(forLegacy: .snowPaper)
        XCTAssertEqual(legacySnow, ThemeSkinSpec.spec(for: .snowPaper))
        let legacyNight = ThemeSkinSpec.spec(forLegacy: .nightVoyage)
        XCTAssertEqual(legacyNight, ThemeSkinSpec.spec(for: .nightVoyage))
    }

    /// 皮肤选择持久化。
    func testSkinStorePersists() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-skin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("s.json")

        let store = ThemeSkinStore(fileURL: url)
        XCTAssertEqual(store.skin, .snowPaper, "默认雪纸")
        try store.setSkin(.peachSoda)

        let reloaded = ThemeSkinStore(fileURL: url)
        XCTAssertEqual(reloaded.skin, .peachSoda, "皮肤选择应持久化")
        XCTAssertEqual(reloaded.spec.accentHex, "#FF6B5A")
    }
}
