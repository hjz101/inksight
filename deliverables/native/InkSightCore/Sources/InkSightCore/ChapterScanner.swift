import Foundation

/// 分章锚点：**只含字节范围与标题，不含正文**（NFR-08：分章只产 `(offset, byteLength)`，
/// 正文永不随主表扫描进内存）。
///
/// 定位铁律的兄弟约束：本结构同样**没有 pageIndex 字段**，也没有任何样式字段。
public struct ChapterAnchor: Equatable, Codable, Sendable {
    /// 章节序号（含虚拟分节）。
    public let index: Int
    /// 章节标记行原文（如「第3章 路上的灯」）；虚拟分节为「未命名章节 · 虚拟分节 i/n」。
    public let title: String
    /// 文件内字节偏移（UTF-8 字节，非字符）。
    public let byteOffset: Int
    public let byteLength: Int

    public init(index: Int, title: String, byteOffset: Int, byteLength: Int) {
        self.index = index
        self.title = title
        self.byteOffset = byteOffset
        self.byteLength = byteLength
    }
}

public struct ChapterScanResult: Sendable {
    public let chapters: [ChapterAnchor]
    /// 扫描耗时（毫秒）。POC-3 判据：20MB ≤100ms（真机、release；预算 40–80ms ＋ 余量）。
    /// 单元测试跑 debug 构建，断言用 1s 硬闸防性能回归，实测值打印留痕。
    public let elapsedMS: Double
    public let totalBytes: Int
    /// 无章节标记整块文本被虚拟分节的段数。
    public let virtualSectionCount: Int
}

public struct ChapterScanConfig: Sendable {
    /// 单章字节上限：超过即按段落边界虚拟分节（POC 文档 §0.7：8–12KB 无标记整块文本）。
    public var maxChunkBytes: Int
    /// 章节标记只在行首这么多字节内匹配。
    public var markerMaxPrefixBytes: Int

    public init(maxChunkBytes: Int = 12_000, markerMaxPrefixBytes: Int = 64) {
        self.maxChunkBytes = maxChunkBytes
        self.markerMaxPrefixBytes = markerMaxPrefixBytes
    }
}

/// 分章扫描器。**字节流扫描，不在打开时解析正文**（技术约束清单 NFR-08）：
/// 找 `\n` 用 Foundation 的 memmem 搜索（`firstRange(of:)`，debug 构建下同样快），
/// 章节标记只在行首 `markerMaxPrefixBytes` 字节内匹配；无章节标记的整块文本
/// 按换行边界虚拟分节，每段 ≤ `maxChunkBytes`。
public enum ChapterScanner {

    /// 章节标记正则：「第X章/回/卷/节/部」「卷N」「Chapter N」。
    /// 候选行才进正则（字节预筛），20MB 只会有几百次正则调用。
    private static let markerRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: "^\\s*(第\\s*[0-9０-９一二三四五六七八九十百千零两]+\\s*[章回卷节集部]|卷\\s*[0-9一二三四五六七八九十百千零两]+|chapter\\s+\\d+)",
            options: [.caseInsensitive, .anchorsMatchLines]
        )
    }()

    private static let newline = Data([0x0A])

    public static func scan(_ data: Data, config: ChapterScanConfig = .init()) -> ChapterScanResult {
        let clock = DispatchTime.now()
        var chapterStarts: [Int] = []
        let n = data.count
        let base = data.startIndex

        // 找行首 + 字节预筛（memmem 快速推进；正则只打候选行）
        var cursor = 0
        while cursor < n {
            if isMarkerCandidate(data, at: cursor, limit: n) {
                chapterStarts.append(cursor)
            }
            guard let r = data.firstRange(of: newline, in: base + cursor..<base + n) else { break }
            cursor = r.upperBound - base
        }

        // 组装章节区间（首行不是标记时补第 0 段）
        var segments: [(start: Int, title: String?)] = chapterStarts.map { ($0, titleAt(data, $0, config)) }
        if segments.first?.start != 0 { segments.insert((0, nil), at: 0) }
        segments.sort { $0.start < $1.start }

        var chapters: [ChapterAnchor] = []
        var virtualSectionCount = 0
        for (i, seg) in segments.enumerated() {
            let end = i + 1 < segments.count ? segments[i + 1].start : n
            let length = end - seg.start
            guard length > 0 else { continue }

            if length <= config.maxChunkBytes {
                chapters.append(ChapterAnchor(
                    index: chapters.count,
                    title: seg.title ?? "未命名章节",
                    byteOffset: seg.start,
                    byteLength: length
                ))
            } else {
                let pieces = splitLargeSegment(data, start: seg.start, end: end, maxChunk: config.maxChunkBytes)
                let total = pieces.count
                for (k, piece) in pieces.enumerated() {
                    let title = seg.title.map { "\($0) · 虚拟分节 \(k + 1)/\(total)" }
                        ?? "未命名章节 · 虚拟分节 \(k + 1)/\(total)"
                    chapters.append(ChapterAnchor(
                        index: chapters.count, title: title,
                        byteOffset: piece.offset, byteLength: piece.length
                    ))
                    virtualSectionCount += 1
                }
            }
        }

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - clock.uptimeNanoseconds) / 1_000_000
        return ChapterScanResult(
            chapters: chapters, elapsedMS: elapsed,
            totalBytes: n, virtualSectionCount: virtualSectionCount
        )
    }

    // MARK: - 内部

    /// 廉价字节预筛：只有「第」「卷」的 UTF-8 前缀或 ASCII `C/c`（Chapter）才值得进正则。
    /// 前导空白最多跳 16 字节——覆盖全角空格（U+3000，3 字节）、制表符与常规缩进
    /// （多段字符串的 8 空格缩进实测把标记藏在了第 9 字节起，跳 4 字节会整条漏掉）。
    private static func isMarkerCandidate(_ data: Data, at p: Int, limit: Int) -> Bool {
        var q = p
        var skipped = 0
        while q < limit && skipped < 16 {
            let b0 = data[q]
            if b0 == 0x20 || b0 == 0x0D || b0 == 0x09 { q += 1; skipped += 1; continue }
            if b0 == 0xE3 && q + 2 < limit && data[q + 1] == 0x80 && data[q + 2] == 0x80 {
                q += 3; skipped += 1; continue     // U+3000 全角空格
            }
            break
        }
        guard q + 2 < limit else { return false }
        let b0 = data[q], b1 = data[q + 1], b2 = data[q + 2]
        if b0 == 0xE7 && b1 == 0xAC && b2 == 0xAC { return true }   // 第
        if b0 == 0xE5 && b1 == 0x8D && b2 == 0xB7 { return true }   // 卷
        if b0 == 0x43 || b0 == 0x63 { return true }                 // C / c（Chapter）
        return false
    }

    private static var base: Int { 0 }   // scan 只对整段 Data 调用；显式化以避免切片索引歧义

    /// 标记行原文。**注意：用 lossy 解码**——`markerMaxPrefixBytes` 截断会切在多字节字符中间，
    /// 严格 UTF-8 解码返回 nil 会把整条标记弄丢（实测：Chapter 3 标记就是这样丢的）。
    private static func titleAt(_ data: Data, _ offset: Int, _ config: ChapterScanConfig) -> String? {
        let upper = min(data.count, offset + config.markerMaxPrefixBytes)
        let window = String(decoding: data[base + offset..<base + upper], as: UTF8.self)
        // 行尾边界：窗口内有 \n 截到行尾；**没有 \n（末行无尾随换行）则取整个窗口**——
        // 两种情况都是行前缀。实测：「第三章 尾声」作为末行（无尾随 \n）曾因强求 \n 被整条弄丢。
        var line = window
        if let nl = window.firstIndex(of: "\n") { line = String(window[..<nl]) }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = markerRegex,
              regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil else { return nil }
        // 标题 = 标记行整行（含章名），不是正则匹配段——「第199章」只是匹配段，
        // 章名「路上的灯」属于标题的一部分（测试 testScan20MBCorrectnessAndTime 抓出过只留匹配段的丢失）。
        return trimmed
    }

    /// 按换行边界切大段：每段 ≤ maxChunkBytes；单段超长（无换行）时按字节硬切。
    ///
    /// **Data 切片保留原始索引**（`Data` 的经典陷阱）：`data[a..<b].lastIndex(of:)`
    /// 返回的是**绝对偏移**，不再加 `a`——加了就是重叠分块（实测：字节总和超过文件体积）。
    private static func splitLargeSegment(_ data: Data, start: Int, end: Int, maxChunk: Int) -> [(offset: Int, length: Int)] {
        var pieces: [(Int, Int)] = []
        var cursor = start
        while cursor < end {
            let remaining = end - cursor
            if remaining <= maxChunk {
                pieces.append((cursor, remaining))
                break
            }
            // 在 [cursor + maxChunk/2, cursor + maxChunk] 内找最后一个换行边界
            var cut = cursor + maxChunk
            let searchStart = cursor + maxChunk / 2
            let searchEnd = min(cut, end - 1)
            if searchEnd > searchStart,
               let nl = data[searchStart..<searchEnd].lastIndex(of: UInt8(0x0A)) {
                cut = nl + 1        // nl 已是绝对偏移（Data 切片保留索引）
            }
            pieces.append((cursor, cut - cursor))
            cursor = cut
        }
        return pieces
    }
}
