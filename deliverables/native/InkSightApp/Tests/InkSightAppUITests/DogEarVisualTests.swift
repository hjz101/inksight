import XCTest
@testable import InkSightAppUI
@testable import InkSightAppKit
import Foundation

/// EGG4 折角**视觉**契约测试（PRD：24→60pt / 保持 3s）。
final class DogEarVisualTests: XCTestCase {

    private func source(_ module: String, _ name: String) throws -> String {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/\(module)")
        let raw = try String(contentsOf: base.appendingPathComponent(name), encoding: .utf8)
        return raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return !t.hasPrefix("//") && !t.hasPrefix("///") && !t.hasPrefix("*")
            }.joined(separator: "\n")
    }

    /// 常量对齐 PRD：24pt 起、60pt 满、保持 3s。
    func testConstantsMatchSpec() {
        XCTAssertEqual(DogEarView.minSize, 24, "PRD：折角 24pt 起")
        XCTAssertEqual(DogEarView.maxSize, 60, "PRD：折角 60pt")
        XCTAssertEqual(DogEarView.holdDuration, 3, "PRD：保持 3s")
    }

    /// 尺寸映射：位移越大折角越大，且**夹取在 24…60**。
    func testSizeMappingClamped() {
        XCTAssertEqual(DogEarView.size(forTranslation: 0), DogEarView.minSize,
                       "未拉动时应为最小尺寸")
        XCTAssertEqual(DogEarView.size(forTranslation: 12), DogEarView.minSize,
                       "吸附阈值起点仍为 24pt")
        XCTAssertEqual(DogEarView.size(forTranslation: 96), DogEarView.maxSize,
                       "拉满应到 60pt")
        XCTAssertEqual(DogEarView.size(forTranslation: 999), DogEarView.maxSize,
                       "超量拉动须夹取到 60pt")
        // 单调递增
        var last: CGFloat = 0
        for t in stride(from: CGFloat(0), through: 96, by: 8) {
            let s = DogEarView.size(forTranslation: t)
            XCTAssertGreaterThanOrEqual(s, last, "尺寸应随位移单调不减")
            last = s
        }
    }

    /// 折角画在右下角（三角形三顶点在右下）。
    func testRendersInBottomRight() throws {
        let src = try source("InkSightAppUI", "DogEarView.swift")
        XCTAssertTrue(src.contains("w - s, y: h"), "三角形须贴右下角")
        XCTAssertTrue(src.contains("alignment: .bottomTrailing")
                      || src.contains("frame(width: size"), "须定位在右下")
    }

    /// 折角**不拦截触摸**（热区由手势层处理，视觉层 allowsHitTesting(false)）。
    func testDoesNotBlockTouches() throws {
        let src = try source("InkSightAppUI", "DogEarView.swift")
        XCTAssertTrue(src.contains("allowsHitTesting(false)"),
                      "折角视觉不得拦截触摸")
    }

    /// 阅读器接线：跟手更新尺寸、吸附后保持 3s。
    func testReaderWiresVisual() throws {
        let src = try source("InkSightAppUI", "ReaderSurface.swift")
        XCTAssertTrue(src.contains("DogEarView(size:"), "阅读器须渲染折角")
        XCTAssertTrue(src.contains("DogEarView.size(forTranslation:"), "跟手须更新尺寸")
        XCTAssertTrue(src.contains("DogEarView.holdDuration"), "吸附后须保持 3s")
        XCTAssertTrue(src.contains("alignment: .bottomTrailing"), "须定位右下角")
    }

    /// 折角颜色取主题墨色/纸面，**不用强调色**（折角是纸的属性，不是交互反馈）。
    func testUsesThemeInkNotAccent() throws {
        let src = try source("InkSightAppUI", "ReaderSurface.swift")
        guard let range = src.range(of: "DogEarView(size:") else {
            return XCTFail("找不到折角渲染")
        }
        let nearby = String(src[range.lowerBound...].prefix(200))
        XCTAssertTrue(nearby.contains("inkHex: theme.textHex"), "折角须用主题墨色")
        XCTAssertFalse(nearby.contains("accentHex"), "折角不得用强调色")
    }
}
