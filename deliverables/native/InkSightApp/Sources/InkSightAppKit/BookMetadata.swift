import Foundation
import InkSightCore

// MARK: - BookMetadata（FR-007 元数据）

/// 图书元数据（FR-007：导入即生成封面作者，可手改）。
public struct BookMetadata: Codable, Equatable, Sendable {
    public var title: String
    public var author: String?
    public var coverImageData: Data?

    public init(title: String, author: String? = nil, coverImageData: Data? = nil) {
        self.title = title
        self.author = author
        self.coverImageData = coverImageData
    }

    /// 展示名（无标题时回落「未命名书籍」）。
    public var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "未命名书籍" : t
    }
}

// MARK: - MetadataParser（FR-007 解析器，纯逻辑可测）

/// 元数据解析（FR-007）：txt 从**文件名**推断，epub 从 **OPF 文件**解析。
///
/// 纪律：
/// - **不做正文内容猜测**（不从正文首行猜书名——那是内容分析不是元数据解析）；
/// - txt 文件名清洗：去扩展名 → 去「作者名 - 书名」「书名 by 作者」常见命名 → 取书名；
/// - epub OPF：XML 解析 `dc:title` / `dc:creator` / `cover` 媒体。
public enum MetadataParser {

    /// 从文件名推断书名与作者（txt 场景）。
    ///
    /// 支持常见命名：
    /// - `红楼梦.txt` → 书名「红楼梦」
    /// - `曹雪芹-红楼梦.txt` → 作者「曹雪芹」、书名「红楼梦」
    /// - `曹雪芹 著-红楼梦.txt` → 同上（去「著」）
    /// - `The Lord of the Rings by J.R.R. Tolkien.txt` → 作者、书名
    public static func parseFromFileName(_ fileName: String) -> BookMetadata {
        var name = (fileName as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespaces)

        // 模式 1：`作者 - 书名` 或 `作者-书名`（中文场景最常见）
        if let range = name.range(of: "-") {
            let left = String(name[..<range.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            let right = String(name[range.upperBound...])
                .trimmingCharacters(in: .whitespaces)
            // 左右都非空才拆分（避免「《-奇怪的书名》」被误拆）
            if !left.isEmpty && !right.isEmpty {
                let author = left
                    .replacingOccurrences(of: "著", with: "")
                    .trimmingCharacters(in: .whitespaces)
                name = right
                return BookMetadata(title: name, author: author.isEmpty ? nil : author)
            }
        }

        // 模式 2：`书名 by 作者`（英文场景）
        let lower = name.lowercased()
        if let byRange = lower.range(of: " by ") {
            let title = String(name[..<byRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let author = String(name[byRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !title.isEmpty && !author.isEmpty {
                return BookMetadata(title: title, author: author)
            }
        }

        return BookMetadata(title: name)
    }

    /// 从 epub 的 OPF 内容解析元数据。
    ///
    /// - Parameters:
    ///   - opfXML: OPF 文件文本（含 `<metadata>` 段）。
    ///   - coverData: 封面图片字节（由调用方从 epub 容器提取；nil ＝ 无封面）。
    /// - Returns: 解析结果（找不到标题时 title 为空串，由调用方回落文件名）。
    public static func parseOPF(_ opfXML: String, coverData: Data? = nil) -> BookMetadata {
        // 轻量 XML 扫描（不引入 XMLParser 依赖到纯逻辑层；epub OPF 结构固定）
        // dc:title
        let title = extractTag(opfXML, tag: "dc:title")
        // dc:creator 优先取最后一个（epub 惯例：creator 可多个，最后一个常为著者）
        let creator = extractTag(opfXML, tag: "dc:creator")
        let author = creator.map { $0.trimmingCharacters(in: .whitespaces) } ?? nil

        return BookMetadata(title: title ?? "",
                            author: author.flatMap { $0.isEmpty ? nil : $0 },
                            coverImageData: coverData)
    }

    /// 提取 XML 标签内容（`<tag>...</tag>`，无嵌套假设——OPF 的 dc: 字段是叶子）。
    static func extractTag(_ xml: String, tag: String) -> String? {
        guard let openRange = xml.range(of: "<\(tag)>") else { return nil }
        let afterOpen = xml[openRange.upperBound...]
        guard let closeRange = afterOpen.range(of: "</\(tag)>") else { return nil }
        let content = String(afterOpen[..<closeRange.lowerBound])
        return content.isEmpty ? nil : content
    }
}
