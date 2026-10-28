import Foundation
import InkSightCore

// MARK: - Highlight / Note（FR-013 划线记笔记）

/// 划线/笔记锚点：**定位一律 `charOffset + length + fingerprint`**（定位铁律同源）。
///
/// - `charOffset`：划线起点（章节纯文本 UTF-16 偏移，与 `PageAnchor` 同口径）；
/// - `length`：划线覆盖的 UTF-16 长度；
/// - `fingerprint`：划线所在段落指纹（换文件/净化后对齐兜底）。
/// 结构上**没有 `pageIndex` 字段**——页码是派生量，落盘即埋雷（定位铁律）。
public struct Highlight: Codable, Equatable, Sendable {
    public let bookID: String
    public let chapterID: Int
    public let charOffset: Int
    public let charLength: Int
    public let fingerprint: UInt64
    /// 划线的选中文本（只作展示快照；跨版本可能失效，定位以 offset/fingerprint 为准）。
    public let selectedText: String
    /// 想法/批注（可为空）。
    public var note: String
    /// 标签（用户自定义，可多个）。
    public var tags: [String]
    /// 创建时间。
    public let createdAt: Date

    public init(bookID: String, chapterID: Int, charOffset: Int, charLength: Int,
                fingerprint: UInt64, selectedText: String, note: String = "",
                tags: [String] = [], createdAt: Date = Date()) {
        self.bookID = bookID
        self.chapterID = chapterID
        self.charOffset = charOffset
        self.charLength = charLength
        self.fingerprint = fingerprint
        self.selectedText = selectedText
        self.note = note
        self.tags = tags
        self.createdAt = createdAt
    }

    /// 从章节文本中提取选中片段（UTF-16 口径；越界返回 nil）。
    public static func selectedText(from chapterText: String,
                                    offset: Int, length: Int) -> String? {
        let ns = chapterText as NSString
        guard offset >= 0, length > 0, offset + length <= ns.length else { return nil }
        return ns.substring(with: NSRange(location: offset, length: length))
    }
}
