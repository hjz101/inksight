import XCTest
@testable import InkSightCore
import CoreText
import AppKit

/// FR-031 判据自测（技术约束清单原文口径）：
/// 标点密集样本上 `CTLineGetTypographicBounds` 与自绘累加 advance 之差 **≤0.5pt**；
/// **>0.5pt 判不可行**。连续两次重测不收敛即升级，不得自行放宽阈值。
final class TypesetterTests: XCTestCase {

    private let typography = ReaderTypography(
        fontID: "PingFangSC-Regular",
        fontSize: 20,
        lineHeightMultiplier: 1.75,          // 行盒 35pt（20×1.75，D-31 行盒）
        paragraphSpacingBefore: 12,
        paragraphSpacingAfter: 0,
        insets: ReaderInsets(top: 24, leading: 20, bottom: 28, trailing: 20),
        indent: 0,
        imagePlaceholderAspect: 3.0 / 4.0
    )
    private let container = CGSize(width: 393, height: 852)

    /// 标点密集样本：连续引号「」／逗号、／破折号——（派单要求的样本形态；本机字符串一律用「」，
    /// 中文直引号 " 会打断 Swift 字面量——D-53 实测坑 ③）
    private let punctuationDense =
        "「『引号连开不闭合』」』」，,、。。！！？？——破折号连用……省略号后接句号。" +
        "「她说，『走吧。』他说：『不。』」——然后，门开了；雨，还在下。、" +
        "「……」！？……——、。，；：」』》〉】）"

    func testFR031PunctuationDenseDeltaWithinHalfPoint() {
        let typesetter = Typesetter(text: punctuationDense, typography: typography,
                                    containerSize: container, kinsoku: .v1)
        let result = typesetter.typesetChapter(chapterID: 0)
        print("FR-031 标点密集样本：maxDelta = \(result.fr031MaxDelta) pt（判据 ≤0.5pt）")
        XCTAssertLessThanOrEqual(result.fr031MaxDelta, 0.5,
            "FR-031 判据失败：actual 与自绘累加之差 >0.5pt，按技术约束清单口径判不可行")
        XCTAssertTrue(result.fr031Passes)
    }

    /// 连续引号/逗号/破折号逐段断言——不允许"平均达标、局部超标"。
    func testFR031EveryLineDeltaWithinHalfPoint() {
        let typesetter = Typesetter(text: punctuationDense, typography: typography,
                                    containerSize: container, kinsoku: .v1)
        let result = typesetter.typesetChapter(chapterID: 0)
        let worst = result.lines.map(\.delta).max() ?? 0
        print("FR-031 逐行最差 delta = \(worst) pt，行数 = \(result.lines.count)")
        XCTAssertLessThanOrEqual(worst, 0.5, "存在单行 delta >0.5pt")
    }

    /// 避头尾：行首不得出现行首禁则字符；行尾不得出现行尾禁则字符。
    func testKinsokuForbiddensNeverViolated() {
        let typesetter = Typesetter(text: punctuationDense + "普通汉字段落随后跟标点。「引号收尾也不行。」",
                                    typography: typography, containerSize: container, kinsoku: .v1)
        let result = typesetter.typesetChapter(chapterID: 0)
        let kinsoku = Kinsoku.v1
        let ns = (punctuationDense + "普通汉字段落随后跟标点。「引号收尾也不行。」") as NSString
        for line in result.lines {
            let startIdx = String.Index(utf16Offset: line.charOffset, in: ns as String)
            let firstChar = (ns as String)[startIdx]
            XCTAssertFalse(kinsoku.lineStartForbidden.contains(firstChar),
                "行首禁则：行 \(line.lineIndex) 以「\(firstChar)」开头")
            let endIdx = String.Index(utf16Offset: line.charOffset + line.charLength - 1, in: ns as String)
            let lastChar = (ns as String)[endIdx]
            XCTAssertFalse(kinsoku.lineEndForbidden.contains(lastChar),
                "行尾禁则：行 \(line.lineIndex) 以「\(lastChar)」结尾")
        }
    }

    /// 页锚点连续全覆盖：首尾相接、无空洞、无重叠（末页到章节结尾）——
    /// 恢复三分支的二分查找成立的前提（D-31 / 技术约束清单 FR-011）。
    func testPageAnchorsContiguouslyCoverChapter() {
        let typesetter = Typesetter(text: punctuationDense, typography: typography,
                                    containerSize: container, kinsoku: .v1)
        let result = typesetter.typesetChapter(chapterID: 7)
        var cursor = 0
        for anchor in result.pages.map(\.anchor) {
            XCTAssertEqual(anchor.charOffset, cursor, "页锚点必须首尾相接（charLength 含段间 \\n）")
            cursor += anchor.charLength
        }
        XCTAssertEqual(cursor, (punctuationDense as NSString).length, "末页必须覆盖到章节结尾")
        XCTAssertEqual(result.pages.map(\.anchor).first?.chapterID, 7)
    }

    /// 定位铁律（⑥）：`PageAnchor` 的 Codable 输出**不可能包含 pageIndex 字段**——
    /// 不是约定不存，是类型里没有。
    func testPageAnchorCodableContainsNoPageIndex() throws {
        let anchor = PageAnchor(chapterID: 1, charOffset: 12, charLength: 340,
                                lineCount: 9, fingerprint: 0xdeadbeef)
        let data = try JSONEncoder().encode(anchor)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let keys = Set((object ?? [:]).keys)
        XCTAssertFalse(keys.contains("pageIndex"), "持久化结构不得出现 pageIndex（定位铁律）")
        XCTAssertTrue(keys.contains("charOffset"))
        XCTAssertTrue(keys.contains("fingerprint"))
    }

    /// 恢复三分支之「二分必命中」：分页连续全覆盖 ⇒ 任意 in-range 偏移必命中唯一页。
    func testBinarySearchAlwaysHits() {
        let typesetter = Typesetter(text: String(repeating: "段落文本，含标点。", count: 120),
                                    typography: typography, containerSize: container, kinsoku: .v1)
        let result = typesetter.typesetChapter(chapterID: 0)
        let anchors = result.pages.map(\.anchor)
        let total = (String(repeating: "段落文本，含标点。", count: 120) as NSString).length
        for offset in stride(from: 0, to: total, by: 37) {
            let hit = anchors.pageContaining(charOffset: offset)
            XCTAssertNotNil(hit, "连续全覆盖下 offset=\(offset) 必然命中")
        }
    }
}
