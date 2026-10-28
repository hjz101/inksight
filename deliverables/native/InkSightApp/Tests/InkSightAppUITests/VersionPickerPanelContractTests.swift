import XCTest
@testable import InkSightAppUI
import Foundation

/// FR-018 文案与结构纪律测试（P0：禁词、主按钮短句、不出现"源名"）。
final class VersionPickerPanelContractTests: XCTestCase {

    private func panelSource() throws -> String {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // InkSightAppUITests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // InkSightApp
            .appendingPathComponent("Sources/InkSightAppUI")
        let raw = try String(contentsOf: base.appendingPathComponent("VersionPickerPanel.swift"),
                             encoding: .utf8)
        // 剥离注释：注释里写「不出现源名」是留痕（合法），不是 UI 文案。
        // 与项目既有源码扫描口径一致（见 ReaderContractTests / PersistTests）。
        return raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return !t.hasPrefix("//") && !t.hasPrefix("///") && !t.hasPrefix("*")
            }
            .joined(separator: "\n")
    }

    /// **禁词**：全本／全本版／全集／完结版／补全／完整版／精校全本 不得出现在 UI 与元数据。
    func testBannedWordsAbsent() throws {
        let src = try panelSource()
        for banned in ["全本", "全集", "完结版", "补全", "完整版", "精校"] {
            XCTAssertFalse(src.contains("\"\(banned)\""),
                           "UI 文案不得含禁词：\(banned)")
            XCTAssertFalse(src.contains("Text(\"\(banned)"),
                           "UI 文案不得含禁词：\(banned)")
        }
    }

    /// **允许**用语存在：换一个版本 / 版本对比 / 位置匹配度。
    func testAllowedTermsPresent() throws {
        let src = try panelSource()
        XCTAssertTrue(src.contains("换一个版本"))
        XCTAssertTrue(src.contains("版本对比"))
        // FR-018 字段列的正式叫法是「位置匹配度」（UI 上「对齐」出现在降级说明里）
        XCTAssertTrue(src.contains("matchText") || src.contains("位置匹配度"),
                      "应展示位置匹配度列")
    }

    /// **主按钮是短句「换一个版本」**；长句保留给无障碍标签。
    func testPrimaryButtonIsShortPhrase() throws {
        let src = try panelSource()
        XCTAssertTrue(src.contains("Text(\"换一个版本\")"), "主按钮应为短句「换一个版本」")
        XCTAssertTrue(src.contains("accessibilityLabel(\"替换为其他版本文件\")"),
                      "长句应保留给无障碍标签（VoiceOver 更准确）")
    }

    /// 副标题 caption：「选择另一份文件，保留进度与笔记」。
    func testSubtitleText() throws {
        let src = try panelSource()
        XCTAssertTrue(src.contains("选择另一份文件，保留进度与笔记"))
    }

    /// pin 行含「当前：」与格式·大小·版本标签。
    func testPinLine() throws {
        let src = try panelSource()
        XCTAssertTrue(src.contains("当前："), "pin 行应以「当前：」开头")
        XCTAssertTrue(src.contains("formatAndSize"))
        XCTAssertTrue(src.contains("versionLabel"))
    }

    /// **不出现「源名」**（本地多副本，不是书源）。
    func testNoSourceName() throws {
        let src = try panelSource()
        XCTAssertFalse(src.contains("\"源名\""), "UI 不得出现「源名」")
        XCTAssertFalse(src.contains("来源"), "UI 不得出现「来源」表述")
    }

    /// 版本标签可编辑（纯文本）。
    func testVersionLabelIsEditable() throws {
        let src = try panelSource()
        XCTAssertTrue(src.contains("TextField"), "版本标签须可编辑")
        XCTAssertTrue(src.contains("versionLabel"), "须展示并可编辑版本标签")
    }
}
