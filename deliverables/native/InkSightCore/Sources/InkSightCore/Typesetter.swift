import Foundation
import CoreText

// MARK: - TypesetLine / TypesetPage / TypesetResult

/// 一行的度量结果。
///
/// `predictedWidth`＝**我方累加**（禁则表裁决断点 ＋ 逐字孤立测距累加）；
/// `actualWidth`＝`CTLineGetTypographicBounds`（CoreText 实测）。
/// **FR-031 判据**：两者之差 ≤0.5pt（>0.5pt 判不可行——技术约束清单原文口径）。
public struct TypesetLine: Sendable {
    /// 章节纯文本 UTF-16 起始偏移。
    public let charOffset: Int
    public let charLength: Int
    public let predictedWidth: Double
    public let actualWidth: Double
    public let delta: Double
    public let lineIndex: Int
    /// 本行是否为某段落的首行（决定段前间距与首行缩进）。
    public let isParagraphStart: Bool
}

/// 一页：锚点 ＋ 组成本页的行。
public struct TypesetPage: Sendable {
    public let anchor: PageAnchor
    public let lines: [TypesetLine]
}

public struct TypesetResult: Sendable {
    public let pages: [TypesetPage]
    public let lines: [TypesetLine]
    /// 全章最大 |actual − predicted|（FR-031 判据观测值）。
    public let fr031MaxDelta: Double
    /// ≤0.5pt 即通过（技术约束清单 FR-031 原文口径）。
    public let fr031Passes: Bool
    public let elapsedMS: Double
}

// MARK: - Typesetter

/// 排版引擎核心：**断点由我方决定，渲染由 CoreText 执行**。
///
/// 构造路径（开发包 #1 派单要求回报的事项）：
/// `CTTypesetterCreateWithAttributedString(_:)`——Swift 覆盖层**接受 NSAttributedString**
/// （隐式桥接 CFAttributedString），直接可用；team-lead 试的 `CTTypesetterCreateString`
/// 与 `CTTypesetter(attr)` 都是错误候选名。
/// **断点不走 `CTTypesetterSuggestLineBreak`**（那是系统断行，会把系统行为带进管线），
/// 而是禁则表＋逐字孤立测距累加求断点，再以 `CTTypesetterCreateLine(ts, 我方range)` 让
/// CoreText 在指定 range 内成行——**零位移不依赖"我们算得和系统一致"，只依赖"结果可复现"**：
/// 字体名称固定＋参数固定＋kern=0，度量就是确定的。
public final class Typesetter {

    private let text: String
    private let utf16Length: Int
    private let typography: ReaderTypography
    private let containerSize: CGSize
    private let kinsokuTable: Kinsoku
    private let attributed: NSAttributedString
    private let typesetter: CTTypesetter
    private let framesetter: CTFramesetter
    private let font: CTFont

    /// 逐字孤立测距（前缀和）：`prefix[i]`＝前 i 个 UTF-16 单元的孤立宽度之和。
    /// 代理对与组合字符按字素整体测一次，续接单元宽度记 0。
    private var prefixAdvance: [Double]
    /// 字素起始的 UTF-16 索引（断点推进按字素走，不按单元）。
    private var graphemeStarts: [Int]
    /// 段落边界（UTF-16 range，按 `\n` 切）与归一化指纹。
    private let paragraphs: [(start: Int, end: Int, fingerprint: UInt64)]

    private var advanceCache: [unichar: Double] = [:]

    /// - Parameters:
    ///   - text: 章节纯文本（来自 `[Paragraph]`，已剥离源样式）。
    ///   - typography: 排版参数唯一来源。
    ///   - containerSize: 容器尺寸（进 `TypographySignature`）。
    ///   - kinsoku: 禁则表（version 参与签名）。
    ///   - fontName: 字体族名（白名单：苹方按名称引用 / 思源宋随包 OFL）。
    ///   - fontSize: 覆盖字号（默认取 typography.fontSize；POC 对照用）。
    public init(text: String,
                typography: ReaderTypography,
                containerSize: CGSize,
                kinsoku: Kinsoku,
                fontName: String = "PingFangSC-Regular",
                fontSize: Double? = nil) {
        self.text = text
        self.utf16Length = (text as NSString).length
        self.typography = typography
        self.containerSize = containerSize
        self.kinsokuTable = kinsoku
        let size = CGFloat(fontSize ?? typography.fontSize)
        self.font = CTFontCreateWithName(fontName as CFString, size, nil)

        // 段落样式：min = max 行高（行盒写死 → lineSpacing 机制性失效，杜绝「1.75＋默认行距」）
        var lineHeight = CGFloat(typography.lineHeight)
        var spacingBefore = CGFloat(typography.paragraphSpacingBefore)
        var spacingAfter = CGFloat(typography.paragraphSpacingAfter)
        var settings: [CTParagraphStyleSetting] = [
            CTParagraphStyleSetting(spec: .minimumLineHeight, valueSize: MemoryLayout<CGFloat>.size, value: &lineHeight),
            CTParagraphStyleSetting(spec: .maximumLineHeight, valueSize: MemoryLayout<CGFloat>.size, value: &lineHeight),
            CTParagraphStyleSetting(spec: .paragraphSpacingBefore, valueSize: MemoryLayout<CGFloat>.size, value: &spacingBefore),
            CTParagraphStyleSetting(spec: .paragraphSpacing, valueSize: MemoryLayout<CGFloat>.size, value: &spacingAfter),
        ]
        let paraStyle = CTParagraphStyleCreate(&settings, settings.count)

        // kern 显式置 0：禁掉上下文 kern，使「孤立测距累加」与「成行实测」可比（FR-031 判据基础）
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTKernAttributeName as String): 0,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paraStyle,
        ]
        self.attributed = NSAttributedString(string: text, attributes: attributes)
        self.typesetter = CTTypesetterCreateWithAttributedString(attributed)
        self.framesetter = CTFramesetterCreateWithAttributedString(attributed)

        // 段落边界与指纹（\n 切分；指纹按段归一化后 FNV-1a 64）
        var paras: [(Int, Int, UInt64)] = []
        let nsText = text as NSString
        var pos = 0
        while pos < nsText.length {
            let nlRange = nsText.range(of: "\n", range: NSRange(location: pos, length: nsText.length - pos))
            let end = nlRange.location == NSNotFound ? nsText.length : nlRange.location
            let piece = nsText.substring(with: NSRange(location: pos, length: end - pos))
            paras.append((pos, end, Fingerprint.fnv1a64(piece)))
            if nlRange.location == NSNotFound { break }
            pos = nlRange.location + 1
        }
        self.paragraphs = paras

        // 逐字孤立测距 + 前缀和 + 字素起点
        var advances = [Double](repeating: 0, count: nsText.length)
        var starts: [Int] = []
        var idx = text.startIndex
        while idx < text.endIndex {
            let next = text.index(after: idx)
            let u0 = idx.utf16Offset(in: text)
            let u1 = next.utf16Offset(in: text)
            starts.append(u0)
            let w = Self.isolatedAdvance(of: String(text[idx..<next]), font: font, cache: &advanceCache)
            if u0 < advances.count { advances[u0] = w }
            idx = next
        }
        if starts.last != nsText.length { starts.append(nsText.length) }
        self.graphemeStarts = starts
        var prefix = [Double](repeating: 0, count: advances.count + 1)
        for i in 0..<advances.count { prefix[i + 1] = prefix[i] + advances[i] }
        self.prefixAdvance = prefix
    }

    // MARK: 排版主入口

    /// 排版整章：自绘断点 → 行（CoreText 在我方 range 内成行）→ 页 → PageAnchor。
    ///
    /// 页装配规则（依技术约束清单 FR-031 / D-31）：
    /// - 行盒 = 字号 × 倍数（min = max，CoreText 的 lineSpacing 机制性失效）；
    /// - 段前间距在「页首段落」清零（`isFirstParagraphOnPage → paragraphSpacingBefore = 0`，
    ///   否则每页首段下移 12pt——CoreText 的段前间距对页首段同样生效，必须显式抑制）；
    /// - 页锚点 `charLength` 与下一页首尾相接（**含段间 `\n`**），保证连续全覆盖。
    public func typesetChapter(chapterID: Int = 0) -> TypesetResult {
        let clock = DispatchTime.now()
        let contentWidth = containerSize.width - typography.insets.leading - typography.insets.trailing
        let contentHeight = containerSize.height - typography.insets.top - typography.insets.bottom
        let lineH = typography.lineHeight

        struct Page { var anchorStart: Int; var lines: [TypesetLine]; var usedHeight: Double }
        var pages: [Page] = []
        var allLines: [TypesetLine] = []
        var maxDelta: Double = 0

        var page = Page(anchorStart: 0, lines: [], usedHeight: 0)
        var lineEnd = 0
        var pos = 0
        var lineIndex = 0

        let fingerprintOfParagraph: (Int) -> UInt64 = { charOffset in
            self.paragraphs.first(where: { charOffset >= $0.start && charOffset < $0.end })?.fingerprint ?? 0
        }
        func nextGraphemeStart(after utf16Offset: Int, limit: Int) -> Int {
            guard utf16Offset < limit else { return limit }
            let idx = String.Index(utf16Offset: utf16Offset, in: text)
            let next = text.index(after: idx)
            return min(next.utf16Offset(in: text), limit)
        }
        func prevGraphemeStart(before utf16Offset: Int, limit: Int) -> Int {
            guard utf16Offset > limit else { return limit }
            let idx = String.Index(utf16Offset: utf16Offset, in: text)
            let prev = text.index(before: idx)
            return max(prev.utf16Offset(in: text), limit)
        }
        func charAt(_ utf16Offset: Int) -> Character {
            text[String.Index(utf16Offset: utf16Offset, in: text)]
        }

        for para in paragraphs {
            guard para.end > para.start else { continue }   // 空段（连续换行）由页锚点 charLength 链覆盖
            var pPos = para.start
            pos = para.start
            var isFirstLineOfParagraph = true

            while pPos < para.end {
                let isPageFirst = page.lines.isEmpty

                // 自绘断点：逐字累加（前缀和），超预算即候选断点（首行段含首行缩进）
                let budget = contentWidth - (isFirstLineOfParagraph ? typography.indent : 0)
                var brk = nextGraphemeStart(after: pPos, limit: para.end)
                while brk < para.end {
                    let next = nextGraphemeStart(after: brk, limit: para.end)
                    if prefixAdvance[next] - prefixAdvance[pPos] > budget { break }
                    brk = next
                }

                // 避头尾裁决（不设 3 次上限——「」』》〉】）可连续 6 个行首禁则字符，
                // 挂上限会把 violation 留在禁则串中段）。悬挂严格前进必然终止；
                // 行尾下移后回检行首（下移的字符可能是行首禁则），总轮次上限 16 防病态振荡。
                var adjustRounds = 0
                var adjusted = true
                while adjusted, adjustRounds < 16 {
                    adjusted = false
                    adjustRounds += 1
                    // 行首禁则 → 标点悬挂到本行行尾（严格前进）
                    while brk < para.end, kinsokuTable.lineStartForbidden.contains(charAt(brk)) {
                        brk = nextGraphemeStart(after: brk, limit: para.end)
                        adjusted = true
                    }
                    // 行尾禁则 → 该字符下移到下一行行首
                    while brk > pPos + 1, kinsokuTable.lineEndForbidden.contains(charAt(brk - 1)) {
                        brk = prevGraphemeStart(before: brk, limit: pPos)
                        adjusted = true
                    }
                }
                if brk <= pPos { brk = nextGraphemeStart(after: pPos, limit: para.end) }

                // 成行（CoreText 只在指定 range 内执行）
                let line = CTTypesetterCreateLine(typesetter, CFRange(location: pos, length: brk - pos))
                var asc: CGFloat = 0, desc: CGFloat = 0, lead: CGFloat = 0
                let actual = CTLineGetTypographicBounds(line, &asc, &desc, &lead)
                let predicted = prefixAdvance[brk] - prefixAdvance[pPos]
                let delta = abs(actual - predicted)
                maxDelta = max(maxDelta, delta)

                // 页装配：段前间距（页首段为 0——D-31 边界：isFirstParagraphOnPage 清零）
                let spacing = (isFirstLineOfParagraph && !isPageFirst) ? typography.paragraphSpacingBefore : 0
                if !isPageFirst, page.usedHeight + spacing + lineH > contentHeight {
                    // 收页：页锚点在函数尾部由 charLength 链式修正统一构造（含 \n，连续全覆盖），此处只切页
                    pages.append(Page(anchorStart: page.anchorStart, lines: page.lines, usedHeight: page.usedHeight))
                    page = Page(anchorStart: lineEnd, lines: [], usedHeight: 0)
                }
                page.usedHeight += spacing + lineH

                let typesetLine = TypesetLine(
                    charOffset: pos,
                    charLength: brk - pos,
                    predictedWidth: predicted,
                    actualWidth: actual,
                    delta: delta,
                    lineIndex: lineIndex,
                    isParagraphStart: isFirstLineOfParagraph
                )
                page.lines.append(typesetLine)
                allLines.append(typesetLine)
                lineEnd = brk
                pos = brk
                pPos = brk
                isFirstLineOfParagraph = false
                lineIndex += 1
                if pos >= para.end { break }
            }
        }
        // 末页：charLength 由下方链式修正统一收口到章节结尾
        pages.append(Page(anchorStart: page.anchorStart, lines: page.lines, usedHeight: page.usedHeight))

        // charLength 链式修正：每页长度 = 下一页起点 − 本页起点（含段间 \n，连续全覆盖）；
        // 末页到章节结尾。这是"每个字符必属且仅属一页"的结构保证（恢复二分必然命中唯一页）。
        var resultPages: [TypesetPage] = []
        var finishedAnchors: [PageAnchor] = []
        for (i, p) in pages.enumerated() {
            let nextStart = i + 1 < pages.count ? pages[i + 1].anchorStart : utf16Length
            let anchor = PageAnchor(
                chapterID: chapterID,
                charOffset: p.anchorStart,
                charLength: nextStart - p.anchorStart,
                lineCount: p.lines.count,
                fingerprint: fingerprintOfParagraph(p.anchorStart)
            )
            finishedAnchors.append(anchor)
            resultPages.append(TypesetPage(anchor: anchor, lines: p.lines))
        }

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - clock.uptimeNanoseconds) / 1_000_000
        return TypesetResult(
            pages: resultPages,
            lines: allLines,
            fr031MaxDelta: maxDelta,
            fr031Passes: maxDelta <= 0.5,
            elapsedMS: elapsed
        )
    }

    // MARK: CTFrame（供 CTFrameCache 用，按页 LRU 7 页）

    /// 头less 建帧（`CTFramesetterCreateFrame` 不需要图形上下文）。
    /// **产物只进内存缓存（LRU 7 页）——严禁任何磁盘写入**：glyph＋字体可经反向 cmap
    /// 还原为 Unicode，视同正文（合规四禁令，架构 v2.4 §二）。
    public func makeFrame(location: Int, length: Int) -> CTFrame {
        let clampedLocation = min(max(0, location), max(0, utf16Length - 1))
        let clampedLength = min(max(1, length), utf16Length - clampedLocation)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: containerSize.width, height: containerSize.height), transform: nil)
        return CTFramesetterCreateFrame(framesetter, CFRange(location: clampedLocation, length: clampedLength), path, nil)
    }

    // MARK: - 内部

    private static func isolatedAdvance(of grapheme: String, font: CTFont, cache: inout [unichar: Double]) -> Double {
        let units = Array(grapheme.utf16)
        guard !units.isEmpty else { return 0 }
        if units.count == 1, let cached = cache[units[0]] { return cached }
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        let mapped = CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count)
        var size = CGSize.zero
        if mapped { CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &size, units.count) }
        let width = Double(size.width)
        if units.count == 1 { cache[units[0]] = width }
        return width
    }
}

// MARK: - KinsokuTable 别名（签名与断点裁决共用同一来源）

public typealias KinsokuTable = Kinsoku
