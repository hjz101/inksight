import XCTest
@testable import InkSightAppUI
import Foundation

/// FR-012 TTS 朗读 UI 契约测试。
final class TTSContractTests: XCTestCase {

    private func source(_ name: String) throws -> String {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/InkSightAppUI")
        let raw = try String(contentsOf: base.appendingPathComponent(name), encoding: .utf8)
        return raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return !t.hasPrefix("//") && !t.hasPrefix("///") && !t.hasPrefix("*")
            }.joined(separator: "\n")
    }

    /// 工具条有「朗读」入口（可见按钮，非手势）。
    func testToolbarHasTTSButton() throws {
        let src = try source("ReaderToolbar.swift")
        XCTAssertTrue(src.contains("朗读"), "工具条须有朗读入口")
        XCTAssertTrue(src.contains("onTTS"), "须有朗读回调")
    }

    /// 面板有播放/暂停、语速、定时关闭（FR-012 三要素）。
    func testPanelHasPlaybackRateAndTimer() throws {
        let src = try source("TTSPanel.swift")
        XCTAssertTrue(src.contains("pause.circle.fill"), "须有播放/暂停")
        XCTAssertTrue(src.contains("语速"), "须有语速控制")
        XCTAssertTrue(src.contains("定时关闭"), "须有定时关闭")
    }

    /// 语速滑杆用 **0.5–2.5** 范围常量（不硬编码）。
    func testRateUsesConstants() throws {
        let src = try source("TTSPanel.swift")
        XCTAssertTrue(src.contains("TTSSettings.minRate"), "语速下界须取常量")
        XCTAssertTrue(src.contains("TTSSettings.maxRate"), "语速上界须取常量")
    }

    /// 面板满足 FR-014 四条可用性。
    func testPanelMeetsFourUsabilityRules() throws {
        let src = try source("TTSPanel.swift")
        XCTAssertTrue(src.contains("width: 44, height: 44"), "44pt 关闭")
        XCTAssertTrue(src.contains("accessibilityAction(.escape)"), ".escape 关闭")
        XCTAssertTrue(src.contains("width: 36, height: 4"), "36×4 把手")
        XCTAssertTrue(src.contains("onTapGesture"), "scrim 点击关闭")
    }

    /// 阅读器退出时停止朗读（不留后台朗读）。
    func testReaderStopsTTSOnExit() throws {
        let src = try source("ReaderSurface.swift")
        XCTAssertTrue(src.contains("tts.stop()"), "退出阅读器须停止朗读")
    }

    /// 朗读从**当前页字符偏移**开始（续读，不跳回章首）。
    func testTTSStartsFromCurrentOffset() throws {
        let src = try source("ReaderSurface.swift")
        XCTAssertTrue(src.contains("startingOffset: offset"), "须从当前页偏移开始朗读")
    }
}
