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

    // MARK: - 本次修复的回归测试（台账待编号）

    /// **回归①：行宽不得超出内容框（超出容差）**。
    ///
    /// 历史缺陷：避头尾裁决把断点前推后**不复查预算**，标点密集处推出远超内容宽的行
    /// （实测默认排版下红楼梦示例 14/141 行溢出、最宽超 22pt；标点密集样本 19/21 行溢出）。
    /// 旧判据 `fr031MaxDelta` 只比对"我方预测 vs 我方成行"，同源恒 0，**结构上查不出**这个缺陷。
    /// 容差＝一个全角字宽：行末标点悬挂是中文出版惯例，允许突出边栏一个字符。
    func testLineWidthNeverExceedsContentBoxBeyondHangingTolerance() {
        let samples: [(String, String)] = [
            ("标点密集", String(repeating: "「これは」』》、。！？abc", count: 40)),
            ("纯中文", String(repeating: "这是一段没有任何禁则标点的普通中文正文内容", count: 40)),
            ("红楼梦节选", "此开卷第一回也。作者自云：因曾历过一番梦幻之后，故将真事隐去，而借通灵之说，撰此《石头记》一书也。"
                + "故曰甄士隐云云。但书中所记何事何人？自又云：今风尘碌碌，一事无成，忽念及当日所有之女子，"
                + "一一细考较去，觉其行止见识，皆出于我之上。何我堂堂须眉，诚不若彼裙钗哉？实愧则有余，悔又无益之大无可如何之日也！"),
        ]
        for (name, text) in samples {
            let result = Typesetter(text: text, typography: typography,
                                    containerSize: container, kinsoku: .v1).typesetChapter(chapterID: 0)
            let tolerance = typography.fontSize   // 一个全角字宽
            XCTAssertLessThanOrEqual(result.maxOverflow, tolerance,
                "\(name)：行宽超出内容框 \(result.maxOverflow)pt > 容差 \(tolerance)pt（内容宽 \(result.contentWidth)pt）")
        }
    }

    /// 溢出判据必须**真的能失败**——用极窄容器构造必然溢出的场景，
    /// 若 `maxOverflow` 恒 0 则说明判据又退化成了恒真式。
    func testOverflowMetricCanActuallyFailOnNarrowContainer() {
        let narrow = CGSize(width: 52, height: 200)   // 内容宽 12pt < 单个全角字 20pt，必然溢出
        let result = Typesetter(text: "这是一段很长很长的中文正文内容用于强制溢出",
                                typography: typography, containerSize: narrow, kinsoku: .v1)
            .typesetChapter(chapterID: 0)
        XCTAssertGreaterThan(result.maxOverflow, 0,
            "极窄容器下必须报出正溢出量；若为 0 说明 maxOverflow 未真正计算")
    }

    /// **回归②：`typography.fontID` 必须真的影响排版度量**。
    ///
    /// 历史缺陷：`Typesetter.init` 收独立 `fontName` 参数字面量默认 "PingFangSC-Regular"，
    /// **从不读 `typography.fontID`**；而渲染侧 `CoreTextLineCompositor` 用 `typography.fontID`。
    /// 换字体后锚点一字不变、但画出来的行宽变了——零位移在绘制阶段破功。
    func testFontIDActuallyAffectsLayoutMetrics() {
        // 注：**中文不行**——全角汉字在多数中文字体里 advance 恒为 1em（20pt），
        // 换字体行宽不变是正确行为。要验证 fontID 是否参与度量，必须用**比例宽度**的拉丁文本。
        let latin = "The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs."
        var ping = typography
        ping.fontID = "PingFangSC-Regular"
        var times = typography
        times.fontID = "Times New Roman"
        var helvetica = typography
        helvetica.fontID = "Helvetica"

        func widths(_ t: ReaderTypography) -> [Double] {
            Typesetter(text: latin, typography: t, containerSize: container, kinsoku: .v1)
                .typesetChapter(chapterID: 0).lines.map(\.predictedWidth)
        }
        let a = widths(ping), b = widths(times), c = widths(helvetica)
        XCTAssertNotEqual(a, b, "PingFang vs Times New Roman 行宽必须不同（fontID 必须参与度量）")
        XCTAssertNotEqual(a, c, "PingFang vs Helvetica 行宽必须不同")
        // 中文字宽恒为 1em，故中文行宽接近但不必刻意断言不同
        let cjk = "此开卷第一回也，作者自云因曾历过一番梦幻之后，故将真事隐去。"
        var s1 = typography; s1.fontID = "PingFangSC-Regular"
        var s2 = typography; s2.fontID = "Songti SC"
        let w1 = Typesetter(text: cjk, typography: s1, containerSize: container, kinsoku: .v1)
            .typesetChapter(chapterID: 0).lines.map(\.predictedWidth)
        let w2 = Typesetter(text: cjk, typography: s2, containerSize: container, kinsoku: .v1)
            .typesetChapter(chapterID: 0).lines.map(\.predictedWidth)
        XCTAssertFalse(w1.isEmpty || w2.isEmpty, "中文字体编排不应产出空行")
    }

    /// **回归③：字体回退字符（主字体缺字形）的测距必须与成行实测一致**。
    ///
    /// 历史缺陷：`CTFontGetGlyphsForCharacters` 对 PingFangSC 缺失的字形（日文假名等）
    /// 返回 false，旧实现把宽度算成 **0**；但 CoreText 成行时会回退到其他字体，真实有宽度。
    /// 后果：`delta` 达 **90pt**（实测标点密集样本含假名时），FR-031 误判不可行。
    func testFontFallbackGlyphsMeasureCorrectly() {
        // 假名不在 PingFangSC 字形表内，必须走回退
        let text = String(repeating: "これは日本語のテキストです。", count: 20)
        let result = Typesetter(text: text, typography: typography,
                                containerSize: container, kinsoku: .v1).typesetChapter(chapterID: 0)
        XCTAssertLessThanOrEqual(result.fr031MaxDelta, 0.5,
            "字体回退字符测距偏差 \(result.fr031MaxDelta)pt > 0.5pt（预期回退宽度曾被算成 0）")
        XCTAssertTrue(result.fr031Passes)
        // 回退字符必须有非零宽度（否则整行会被误判为空行）
        XCTAssertGreaterThan(result.lines.map(\.predictedWidth).max() ?? 0, 0)
    }
}
