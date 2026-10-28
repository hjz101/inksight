import Foundation

// MARK: - 渲染输入契约（FR-031：渲染层唯一输入）

/// 段落类型。技术约束清单 FR-031：渲染输入只有 `[Paragraph]`（type: text / image / title）
/// ＋ `ReaderTypography` 单一排版来源；渲染层不得接收 AttributedString，不得含任何 HTML。
public enum ParagraphKind: String, Codable, Sendable, CaseIterable {
    case text
    case image
    case title
}

/// 结构化段落。
///
/// 定位铁律的实现约束之一：本结构**不携带任何样式字段**（无 font / color / indent），
/// 因此「源样式残留」在类型层就是不可能表达的——`sourceStyleResidual` 只能来自文本泄漏检测。
/// 同样地，本结构**没有 pageIndex 字段**（定位铁律：持久化不以页码为依据）。
public struct Paragraph: Equatable, Codable, Sendable {
    public let kind: ParagraphKind
    public let text: String
    /// image 段的引用列表（src）；text / title 段为空数组。
    public let imageReferences: [String]
    public let order: Int

    public init(kind: ParagraphKind, text: String, imageReferences: [String] = [], order: Int) {
        self.kind = kind
        self.text = text
        self.imageReferences = imageReferences
        self.order = order
    }
}

/// StyleStripper 的产出。
public struct StripOutcome: Equatable, Sendable {
    public let paragraphs: [Paragraph]
    /// 验收 AC-1（技术约束清单原文）：渲染输入中残留的源样式数，**必须 == 0**。
    public let sourceStyleResidual: Int
    /// 健康度观测项：解析器剥离了多少条源样式（**正常应 > 0**；归零说明解析器没生效）。
    public let strippedStyleCount: Int
}

// MARK: - StyleStripper

/// 解析层：**唯一接触 HTML 的环节**。源侧任何 `style` / `class` / `font` /
/// `text-indent` 在此丢弃，输出只含结构化段落——换源零位移由此保证（渲染层不接收任何源样式）。
public enum StyleStripper {

    /// 元提及检测用的特征串：出现在**输出文本**里即视为源样式泄漏（sourceStyleResidual）。
    static let residualMarkers: [String] = ["style=", "class=", "font-size", "font-family", "text-indent", "color="]
    /// 剥离计数用的特征串：出现在**标签内**即计入 strippedStyleCount。
    static let strippedMarkers: [String] = residualMarkers

    public static func strip(html: String) -> StripOutcome {
        var paragraphs: [Paragraph] = []
        var buffer = ""
        var strippedStyleCount = 0
        var currentKind: ParagraphKind = .text
        var order = 0

        func flush() {
            let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { buffer = ""; return }
            let text = decodeEntities(trimmed)
            paragraphs.append(Paragraph(kind: currentKind, text: text, imageReferences: [], order: order))
            order += 1
            buffer = ""
            currentKind = .text
        }

        var index = html.startIndex
        while index < html.endIndex {
            let ch = html[index]
            if ch == "<", let tagEnd = html[index...].firstIndex(of: ">") {
                let tagBody = String(html[html.index(after: index)..<tagEnd])
                let trimmedBody = tagBody.trimmingCharacters(in: .whitespaces)
                let isClosing = trimmedBody.hasPrefix("/")
                let name = tagName(of: tagBody)

                // 属性剥离计数：标签内命中 style / class / font-* / text-indent / color 即计入
                for marker in strippedMarkers where tagBody.lowercased().contains(marker) {
                    strippedStyleCount += 1
                }

                switch name {
                case "br":
                    flush()
                case "img":
                    flush()
                    if let src = attribute(named: "src", in: tagBody) {
                        paragraphs.append(Paragraph(kind: .image, text: "", imageReferences: [src], order: order))
                        order += 1
                    }
                case "h1", "h2", "h3", "h4", "h5", "h6":
                    // 开标签 → 后续文本是标题；闭标签 → 恢复正文（否则标题后的段落会被误标为 title）
                    flush()
                    currentKind = isClosing ? .text : .title
                case "p", "div", "li", "section", "blockquote":
                    flush()
                case "script", "style":
                    // 整段丢弃到对应闭合标签
                    if let close = html.range(of: "</\(name)", range: tagEnd..<html.endIndex),
                       let gt = html[close.upperBound...].firstIndex(of: ">") {
                        index = gt
                        // 注意：script/style 内的文本不进任何段落，也不计残差
                        index = html.index(after: index)
                        continue
                    }
                default:
                    break
                }
                index = html.index(after: tagEnd)
            } else {
                buffer.append(ch)
                index = html.index(after: index)
            }
        }
        flush()

        // sourceStyleResidual：输出文本中的源样式泄漏检测（AC-1：必须 == 0）
        let residual = paragraphs.reduce(0) { count, p in
            count + residualMarkers.filter { p.text.lowercased().contains($0) }.count
        }

        return StripOutcome(paragraphs: paragraphs, sourceStyleResidual: residual, strippedStyleCount: strippedStyleCount)
    }

    private static func tagName(of tagBody: String) -> String {
        let trimmed = tagBody.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return "" }
        if first == "/" { return String(trimmed.dropFirst()).lowercased() }
        let name = trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? trimmed
        return name.lowercased()
    }

    private static func attribute(named name: String, in tagBody: String) -> String? {
        let key = name.lowercased()
        for pattern in ["\(key)=\"", "\(key)='"] {
            if let r = tagBody.range(of: pattern, options: .caseInsensitive) {
                let quote = pattern.hasSuffix("\"") ? "\"" : "'"
                var rest = tagBody[r.upperBound...]
                if let end = rest.firstIndex(of: Character(quote)) {
                    rest = rest[..<end]
                    return String(rest)
                }
            }
        }
        return nil
    }

    private static func decodeEntities(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "&nbsp;", with: " ")
        out = out.replacingOccurrences(of: "&lt;", with: "<")
        out = out.replacingOccurrences(of: "&gt;", with: ">")
        out = out.replacingOccurrences(of: "&quot;", with: "”")
        out = out.replacingOccurrences(of: "&amp;", with: "&")
        return out
    }
}
