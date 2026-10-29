import Foundation
import InkSightCore

// MARK: - EpubExtractor（FR-007：epub 容器解包取元数据与封面）

/// epub 解包（FR-007 的补齐：此前 `parseOPF` 只吃 OPF 文本，**取 OPF 需解包**）。
///
/// epub 结构（规范最小集）：
/// 1. `META-INF/container.xml` → 指向 OPF 路径；
/// 2. OPF 文件 → `dc:title` / `dc:creator` / manifest 里的封面条目；
/// 3. 封面图片 → 字节。
///
/// **降级诚实**：任一环节缺失就返回**已拿到的部分**，`coverData` 为 nil 而非编造。
public enum EpubExtractor {

    /// 解包结果。
    public struct Result: Equatable, Sendable {
        public let metadata: BookMetadata
        /// OPF 路径（诊断用；nil ＝ 没找到 container/OPF）。
        public let opfPath: String?

        public init(metadata: BookMetadata, opfPath: String?) {
            self.metadata = metadata
            self.opfPath = opfPath
        }
    }

    /// 从 epub 字节解包。
    ///
    /// - Parameter data: `.epub` 文件字节。
    /// - Returns: 元数据（标题可能为空串，由调用方回落文件名）。
    /// - Throws: 不是 zip / 读取失败时抛错——**不静默返回空元数据**
    ///   （静默会让导入"成功"但书名空白，用户不知道发生了什么）。
    public static func extract(from data: Data) throws -> Result {
        let zip = try ZipReader(data: data)
        guard let opfPath = try? locateOPF(in: zip) else {
            // 没有 container.xml：兜底扫根目录第一个 .opf（部分工具产出的 epub 没有 container）
            if let fallback = zip.entries.first(where: { $0.name.hasSuffix(".opf") }) {
                return try parseOPFEntry(named: fallback.name, in: zip)
            }
            throw ZipReader.ZipError.entryNotFound("OPF")
        }
        return try parseOPFEntry(named: opfPath, in: zip)
    }

    /// 读 `META-INF/container.xml` 拿 OPF 路径。
    static func locateOPF(in zip: ZipReader) throws -> String {
        let containerData = try zip.read("META-INF/container.xml")
        let xml = String(decoding: containerData, as: UTF8.self)
        // container.xml 的 <rootfile full-path="...">
        guard let path = attribute("full-path", in: xml), !path.isEmpty else {
            throw ZipReader.ZipError.entryNotFound("OPF 路径")
        }
        return path
    }

    /// 解析 OPF（含封面提取）。
    static func parseOPFEntry(named path: String, in zip: ZipReader) throws -> Result {
        let opfData = try zip.read(path)
        let opfXML = String(decoding: opfData, as: UTF8.self)

        // 封面：优先 metadata 的 <meta name="cover" content="id">，回退 manifest 的 media-type 前缀 image
        let coverData = extractCover(opfXML: opfXML, opfPath: path, zip: zip)
        let metadata = MetadataParser.parseOPF(opfXML, coverData: coverData)
        return Result(metadata: metadata, opfPath: path)
    }

    /// 从 OPF 找封面条目并读取字节。
    static func extractCover(opfXML: String, opfPath: String, zip: ZipReader) -> Data? {
        // ① <meta name="cover" content="cover-image"/>
        if let coverID = metaCoverID(opfXML),
           let href = manifestHref(forID: coverID, in: opfXML) {
            let resolved = resolve(href: href, relativeTo: opfPath)
            if let data = try? zip.read(resolved) { return data }
        }
        // ② manifest 里第一个 media-type="image/..." 且 id/href 含 cover 的
        if let href = firstImageWithCoverHint(in: opfXML) {
            let resolved = resolve(href: href, relativeTo: opfPath)
            if let data = try? zip.read(resolved) { return data }
        }
        // ③ 兜底：容器里第一个常见图片扩展名且名字含 cover
        if let entry = zip.entries.first(where: {
            let n = $0.name.lowercased()
            return n.contains("cover") && (n.hasSuffix(".jpg") || n.hasSuffix(".jpeg")
                                           || n.hasSuffix(".png"))
        }), let data = try? zip.read(entry.name) {
            return data
        }
        return nil
    }

    // MARK: - XML 轻量提取

    /// 提取某标签的某属性值（`<tag ... attr="value">`）。
    static func attribute(_ name: String, in xml: String) -> String? {
        // 找 name=" 后到下一个引号
        guard let r = xml.range(of: "\(name)=\"") else { return nil }
        let rest = xml[r.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    /// `<meta name="cover" content="ID"/>` 的 ID。
    static func metaCoverID(_ xml: String) -> String? {
        // 逐段扫 <meta ...>，找 name="cover" 那一段的 content
        var searchRange = xml.startIndex..<xml.endIndex
        while let open = xml.range(of: "<meta", range: searchRange) {
            guard let close = xml.range(of: ">", range: open.upperBound..<xml.endIndex) else { break }
            let tag = String(xml[open.lowerBound..<close.upperBound])
            if tag.contains("name=\"cover\""), let content = attribute("content", in: tag) {
                return content
            }
            searchRange = close.upperBound..<xml.endIndex
        }
        return nil
    }

    /// 按 id 找 manifest 里的 href。
    static func manifestHref(forID id: String, in xml: String) -> String? {
        var searchRange = xml.startIndex..<xml.endIndex
        while let open = xml.range(of: "<item", range: searchRange) {
            guard let close = xml.range(of: ">", range: open.upperBound..<xml.endIndex) else { break }
            let tag = String(xml[open.lowerBound..<close.upperBound])
            if let itemID = attribute("id", in: tag), itemID == id {
                return attribute("href", in: tag)
            }
            searchRange = close.upperBound..<xml.endIndex
        }
        return nil
    }

    /// 第一个含 cover 线索的图片 href。
    static func firstImageWithCoverHint(in xml: String) -> String? {
        var searchRange = xml.startIndex..<xml.endIndex
        while let open = xml.range(of: "<item", range: searchRange) {
            guard let close = xml.range(of: ">", range: open.upperBound..<xml.endIndex) else { break }
            let tag = String(xml[open.lowerBound..<close.upperBound])
            let media = attribute("media-type", in: tag) ?? ""
            if media.hasPrefix("image/") {
                let id = attribute("id", in: tag) ?? ""
                let href = attribute("href", in: tag) ?? ""
                let hint = (id + href).lowercased()
                if hint.contains("cover") { return href.isEmpty ? nil : href }
            }
            searchRange = close.upperBound..<xml.endIndex
        }
        return nil
    }

    /// href 相对 OPF 所在目录解析（`OEBPS/content.opf` + `images/cover.jpg` → `OEBPS/images/cover.jpg`）。
    static func resolve(href: String, relativeTo opfPath: String) -> String {
        if href.hasPrefix("/") { return String(href.dropFirst()) }
        let dir = (opfPath as NSString).deletingLastPathComponent
        if dir.isEmpty { return href }
        // 处理 ../（规范化）
        var parts = ("\(dir)/\(href)" as NSString).components(separatedBy: "/")
        var stack: [String] = []
        for p in parts {
            if p == ".." { if !stack.isEmpty { stack.removeLast() } }
            else if p != "." && !p.isEmpty { stack.append(p) }
        }
        parts = stack
        return parts.joined(separator: "/")
    }
}
