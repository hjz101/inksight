import Foundation
import InkSightCore

// MARK: - EpubTextExtractor（FR-007：epub 正文提取）

/// epub 正文提取：把 zip 里的 XHTML 章节按 **spine 顺序**抽成纯文本。
///
/// **为什么需要它**：`ChapterAnchor` 按**字节偏移**定位，而 epub 正文在压缩的
/// XHTML 里——字节偏移无法映射进 zip。故策略是「**导入时提取为本地 txt 缓存**」，
/// 之后完全走既有 txt 链路（`ChapterScanner` + 字节切片），
/// **`ChapterAnchor` 契约一个字都不用改**。
///
/// epub spine（阅读顺序）：
/// 1. `META-INF/container.xml` → OPF 路径；
/// 2. OPF 的 `<manifest>` 给 id→href；
/// 3. OPF 的 `<spine>` 按顺序列 `<itemref idref="...">`；
/// 4. 逐个读 XHTML → 去标签 → 纯文本。
public enum EpubTextExtractor {

    /// 提取结果。
    public struct Result: Equatable, Sendable {
        /// 纯文本正文（**已按 spine 顺序拼接**，段落以 `\n` 分隔）。
        public let text: String
        /// 各章节（spine 项）的标题（来自 XHTML 的 `<title>` 或首个 `<h1>`~`<h3>`）。
        public let chapterTitles: [String]

        public init(text: String, chapterTitles: [String]) {
            self.text = text
            self.chapterTitles = chapterTitles
        }
    }

    /// 从 epub 字节提取正文。
    ///
    /// - Throws: 解包失败/无 spine 时抛错（**不返回空文本假装成功**——
    ///   返回空会让书架上出现一本"打开是空白"的书）。
    public static func extract(from data: Data) throws -> Result {
        let zip = try ZipReader(data: data)
        let opfPath = try locateOPF(in: zip)
        let opfXML = String(decoding: try zip.read(opfPath), as: UTF8.self)

        let manifest = parseManifest(opfXML)
        let spine = parseSpine(opfXML)
        guard !spine.isEmpty else {
            throw ZipReader.ZipError.entryNotFound("spine")
        }

        var pieces: [String] = []
        var titles: [String] = []

        for idref in spine {
            guard let href = manifest[idref] else { continue }
            let path = EpubExtractor.resolve(href: href, relativeTo: opfPath)
            guard let raw = try? zip.read(path) else { continue }
            let xhtml = String(decoding: raw, as: UTF8.self)
            let body = extractBody(from: xhtml)
            let text = stripMarkup(body)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }   // 空章（纯图片页）跳过
            // 标题：<title> → 首个 h1/h2/h3 → 兜底
            let title = firstMatch(xhtml, pattern: "<title[^>]*>(.*?)</title>")
                ?? firstMatch(xhtml, pattern: "<h[1-3][^>]*>(.*?)</h[1-3]>")
                ?? "第 \(titles.count + 1) 节"
            titles.append(stripMarkup(title).trimmingCharacters(in: .whitespacesAndNewlines))
            pieces.append(trimmed)
        }

        guard !pieces.isEmpty else {
            throw ZipReader.ZipError.entryNotFound("可读正文")
        }
        return Result(text: pieces.joined(separator: "\n\n"), chapterTitles: titles)
    }

    // MARK: - OPF 结构

    /// 解析 manifest：id → href。
    static func parseManifest(_ xml: String) -> [String: String] {
        var map: [String: String] = [:]
        var range = xml.startIndex..<xml.endIndex
        while let open = xml.range(of: "<item", range: range) {
            guard let close = xml.range(of: ">", range: open.upperBound..<xml.endIndex) else { break }
            let tag = String(xml[open.lowerBound..<close.upperBound])
            if let id = attribute("id", in: tag), let href = attribute("href", in: tag) {
                map[id] = href
            }
            range = close.upperBound..<xml.endIndex
        }
        return map
    }

    /// 解析 spine：按顺序的 idref 列表。
    static func parseSpine(_ xml: String) -> [String] {
        guard let spineOpen = xml.range(of: "<spine") else { return [] }
        guard let spineClose = xml.range(of: "</spine>",
                                        range: spineOpen.upperBound..<xml.endIndex) else {
            // 自闭合或无闭合：取到 manifest 之后的内容
            let tail = xml[spineOpen.upperBound...]
            return collectItemrefs(String(tail))
        }
        let inner = String(xml[spineOpen.upperBound..<spineClose.lowerBound])
        return collectItemrefs(inner)
    }

    private static func collectItemrefs(_ s: String) -> [String] {
        var out: [String] = []
        var range = s.startIndex..<s.endIndex
        while let open = s.range(of: "<itemref", range: range) {
            guard let close = s.range(of: ">", range: open.upperBound..<s.endIndex) else { break }
            let tag = String(s[open.lowerBound..<close.upperBound])
            if let idref = attribute("idref", in: tag) { out.append(idref) }
            range = close.upperBound..<s.endIndex
        }
        return out
    }

    // MARK: - XHTML → 纯文本

    /// 取 `<body>` 内容（无 body 则取全文）。
    static func extractBody(from xhtml: String) -> String {
        if let open = xhtml.range(of: "<body"),
           let openEnd = xhtml.range(of: ">", range: open.upperBound..<xhtml.endIndex),
           let close = xhtml.range(of: "</body>", range: openEnd.upperBound..<xhtml.endIndex) {
            return String(xhtml[openEnd.upperBound..<close.lowerBound])
        }
        return xhtml
    }

    /// 去标签 → 纯文本。
    ///
    /// 关键处理：
    /// - **块级元素边界换行**（`<p>`/`<div>`/`<br>`/`<h1..6>`）——否则段落会粘成一行；
    /// - 解码常见 HTML 实体（`&amp;` `&lt;` `&nbsp;` 等）；
    /// - 折叠连续空白（**但保留段落换行**）。
    static func stripMarkup(_ s: String) -> String {
        var out = s
        // 1) 块级边界 → 换行（先做，避免被后续去标签连成一片）
        let blockTags = ["</p>", "</div>", "<br/>", "<br />", "<br>",
                         "</h1>", "</h2>", "</h3>", "</h4>", "</h5>", "</h6>",
                         "</li>", "</blockquote>"]
        for tag in blockTags {
            out = out.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }
        // 2) 去 script/style 整段（内容不是正文）
        out = removeElement("script", from: out)
        out = removeElement("style", from: out)
        // 3) 去剩余标签
        out = removeRegex(out, pattern: "<[^>]+>")
        // 4) 实体解码
        let entities: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"),
            ("&mdash;", "—"), ("&ndash;", "–"), ("&hellip;", "…"),
            ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"),
            ("&lsquo;", "\u{2018}"), ("&rsquo;", "\u{2019}"),
        ]
        for (e, c) in entities { out = out.replacingOccurrences(of: e, with: c) }
        // 5) 行内空白折叠（保留换行）
        let lines = out.components(separatedBy: "\n").map { line -> String in
            line.replacingOccurrences(of: "\t", with: " ")
                .split(separator: " ", omittingEmptySubsequences: true)
                .joined(separator: " ")
        }
        // 6) 连续空行折叠为一个
        var result: [String] = []
        var lastWasBlank = false
        for line in lines {
            let blank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if blank {
                if !lastWasBlank { result.append("") }
                lastWasBlank = true
            } else {
                result.append(line)
                lastWasBlank = false
            }
        }
        return result.joined(separator: "\n")
    }

    private static func removeElement(_ name: String, from s: String) -> String {
        var out = s
        while let open = out.range(of: "<\(name)", options: .caseInsensitive),
              let openEnd = out.range(of: ">", range: open.upperBound..<out.endIndex),
              let close = out.range(of: "</\(name)>", options: .caseInsensitive,
                                    range: openEnd.upperBound..<out.endIndex) {
            out.removeSubrange(open.lowerBound..<close.upperBound)
        }
        return out
    }

    private static func removeRegex(_ s: String, pattern: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern,
                                               options: [.dotMatchesLineSeparators]) else {
            return s
        }
        let range = NSRange(location: 0, length: (s as NSString).length)
        return re.stringByReplacingMatches(in: s, range: range, withTemplate: "")
    }

    private static func firstMatch(_ s: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern,
                                               options: [.dotMatchesLineSeparators, .caseInsensitive])
        else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let r = tag.range(of: "\(name)=\"") else {
            // 也接受单引号
            guard let r2 = tag.range(of: "\(name)='") else { return nil }
            let rest = tag[r2.upperBound...]
            guard let end = rest.firstIndex(of: "'") else { return nil }
            return String(rest[..<end])
        }
        let rest = tag[r.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    private static func locateOPF(in zip: ZipReader) throws -> String {
        do { return try EpubExtractor.locateOPF(in: zip) }
        catch {
            if let fallback = zip.entries.first(where: { $0.name.hasSuffix(".opf") }) {
                return fallback.name
            }
            throw error
        }
    }
}
