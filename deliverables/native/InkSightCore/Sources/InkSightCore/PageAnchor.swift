import Foundation
import CoreText

// MARK: - PageAnchor（定位契约，原生阶段冻结项）

/// 页锚点：**定位一律 `charOffset + fingerprint`，不以页码为依据**（定位铁律）。
///
/// 契约（原生阶段冻结项，写完不许静默改；要改走台账新编号）：
/// 1. 本结构**没有 pageIndex 字段**——不是"约定不存"，是**类型里没有**：
///    持久化铁律由类型设计保证（Codable 输出也不可能出现该字段，见测试 ⑥）。
/// 2. `charOffset` 基准＝**章节纯文本的 UTF-16 偏移**（不用 String.Index——不可序列化、
///    跨版本不稳；不用字符数——代理对会算错）。
/// 3. `fingerprint`＝页首所在段落的 FNV-1a 64 指纹（归一化后），用于换文件/净化后
///    charOffset 越界时的对齐兜底。
/// 4. 分页连续全覆盖：每个字符必属且仅属一页，二分查找必然命中唯一页；
///    「页首偏移 > charOffset」这个分支不存在，越界走 clamp→指纹→章首（恢复三分支）。
public struct PageAnchor: Equatable, Codable, Sendable {
    public let chapterID: Int
    /// 章节纯文本 UTF-16 偏移（页首字符）。
    public let charOffset: Int
    /// 本页覆盖的 UTF-16 长度（与下一页首尾相接、连续全覆盖）。
    public let charLength: Int
    public let lineCount: Int
    /// 页首所在段落的归一化指纹。
    public let fingerprint: UInt64

    public init(chapterID: Int, charOffset: Int, charLength: Int, lineCount: Int, fingerprint: UInt64) {
        self.chapterID = chapterID
        self.charOffset = charOffset
        self.charLength = charLength
        self.lineCount = lineCount
        self.fingerprint = fingerprint
    }
}

public extension Sequence where Element == PageAnchor {
    /// 按 `charOffset` 二分定位：返回包含该偏移的页（分页连续全覆盖，必然命中）。
    /// 越界（offset ≥ 章节总长）返回 nil——上层按恢复三分支处理（clamp→指纹→章首）。
    func pageContaining(charOffset: Int) -> PageAnchor? {
        let sorted = self.sorted { $0.charOffset < $1.charOffset }
        var low = 0, high = sorted.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let anchor = sorted[mid]
            if charOffset < anchor.charOffset {
                high = mid - 1
            } else if charOffset >= anchor.charOffset + anchor.charLength {
                low = mid + 1
            } else {
                return anchor
            }
        }
        return nil
    }
}

// MARK: - 指纹

/// FNV-1a 64。输入为**归一化后**的段落文本（全角→半角、去空白、去标点）；
/// 归一化只在指纹计算内部做，`charOffset` 永远基于原始文本（offset 稳定、指纹容忍排版差异）。
///
/// 高熵说明（合规）：指纹输入是数百字段落文本，哈希不可反查——
/// 与「域名等低熵输入哈希＝明文」是两回事，判据是**输入熵**不是"是否哈希"。
public enum Fingerprint {
    public static func fnv1a64(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for unit in normalize(text).utf16 {
            hash ^= UInt64(unit & 0xFF)
            hash = hash &* 0x00000100000001b3
            hash ^= UInt64((unit >> 8) & 0xFF)
            hash = hash &* 0x00000100000001b3
        }
        return hash
    }

    static func normalize(_ text: String) -> String {
        let forbidden = "，。、；：？！」』）】》〉…‥—～・!?),.;:]}\"'「『（《【〈“‘([{ \t\n\r"
        return String(text.lowercased().filter { !forbidden.contains($0) })
    }
}

// MARK: - PageAnchorCache（LRU 10 章，D-52 勘误值）

/// `PageAnchor` 缓存：**LRU 10 章**（架构 v1.9 勘误值；PageAnchor 非正文，
/// 不受"会话内存 ≤3 章"合规约束——那是正文的约束）。
///
/// O(1) 全作废：**世代号机制**——`invalidateAll()` 只递增 generation，
/// 旧条目因世代不匹配而失配（不遍历、不删除）。签名变化即调用本方法。
public final class PageAnchorCache: @unchecked Sendable {

    public static let defaultCapacity = 10

    private struct Entry {
        let signatureHash: String
        let chapterID: Int
        let generation: Int
        var anchors: [PageAnchor]
        var lastUse: Int
    }

    private let capacity: Int
    private var entries: [Entry] = []
    private var generation = 0
    private var clock = 0
    private let lock = NSLock()

    public init(capacity: Int = PageAnchorCache.defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    public func anchors(for chapterID: Int, signatureHash: String) -> [PageAnchor]? {
        lock.lock(); defer { lock.unlock() }
        clock += 1
        let now = clock
        if let idx = entries.lastIndex(where: { $0.signatureHash == signatureHash && $0.chapterID == chapterID && $0.generation == generation }) {
            entries[idx].lastUse = now
            return entries[idx].anchors
        }
        return nil
    }

    public func store(_ anchors: [PageAnchor], for chapterID: Int, signatureHash: String) {
        lock.lock(); defer { lock.unlock() }
        clock += 1
        let now = clock
        if let idx = entries.lastIndex(where: { $0.signatureHash == signatureHash && $0.chapterID == chapterID && $0.generation == generation }) {
            entries[idx].anchors = anchors
            entries[idx].lastUse = now
            return
        }
        if entries.count >= capacity, let oldest = entries.indices.min(by: { entries[$0].lastUse < entries[$1].lastUse }) {
            entries.remove(at: oldest)
        }
        entries.append(Entry(signatureHash: signatureHash, chapterID: chapterID, generation: generation, anchors: anchors, lastUse: now))
    }

    /// O(1) 全作废（签名变化即调用）。世代号 +1，全部旧条目失配，不遍历不删除。
    public func invalidateAll() {
        lock.lock(); defer { lock.unlock() }
        generation += 1
        entries.removeAll(keepingCapacity: true)
    }
}

// MARK: - CTFrameCache（按页 LRU 7 页，D-52 勘误值）

/// `CTFrame` 缓存 key。**不含 pageIndex**——页以 `(chapterID, charOffset)` 唯一确定
/// （页码是派生值，签名不匹配即丢弃；用它做 key 会让缓存依赖一个会漂移的量）。
public struct CTFrameCacheKey: Equatable, Hashable, Sendable {
    public let chapterID: Int
    public let charOffset: Int
    public let signatureHash: String

    public init(chapterID: Int, charOffset: Int, signatureHash: String) {
        self.chapterID = chapterID
        self.charOffset = charOffset
        self.signatureHash = signatureHash
    }
}

/// `CTFrame` 按页缓存：**LRU 7 页（当前 ±3，D-52 勘误值）**，内存 ≈420KB。
///
/// 合规四禁令（合规侧书面归档，架构 v2.4 §二）——本缓存**只在内存**：
/// 1. 不写入任何磁盘路径（`Caches/`、`tmp/`、`Application Support/` 全部禁）；
/// 2. 不进崩溃快照（**含 `MetricKit` 的 `diagnostic` 包**）；
/// 3. 不进内存转储文件；
/// 4. 切书或会话结束即释放（调用 `invalidateAll`）。
/// 判据："是否形成稳定可再现的副本"——glyph＋字体可经反向 cmap 还原为 Unicode，故视同正文。
/// **尤其"序列化到磁盘加速二次打开"＝正文落盘＝违规**：理由充分、无人反对、无声违规，必须点名列禁。
public final class CTFrameCache: @unchecked Sendable {

    public static let defaultCapacity = 7

    private struct Entry {
        let key: CTFrameCacheKey
        var frame: CTFrame
        var lastUse: Int
    }

    private let capacity: Int
    private var entries: [Entry] = []
    private var clock = 0
    private let lock = NSLock()

    public init(capacity: Int = CTFrameCache.defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    public func frame(for key: CTFrameCacheKey) -> CTFrame? {
        lock.lock(); defer { lock.unlock() }
        clock += 1
        if let idx = entries.firstIndex(where: { $0.key == key }) {
            entries[idx].lastUse = clock
            return entries[idx].frame
        }
        return nil
    }

    public func store(_ frame: CTFrame, for key: CTFrameCacheKey) {
        lock.lock(); defer { lock.unlock() }
        clock += 1
        if let idx = entries.firstIndex(where: { $0.key == key }) {
            entries[idx].frame = frame
            entries[idx].lastUse = clock
            return
        }
        if entries.count >= capacity, let oldest = entries.indices.min(by: { entries[$0].lastUse < entries[$1].lastUse }) {
            entries.remove(at: oldest)
        }
        entries.append(Entry(key: key, frame: frame, lastUse: clock))
    }

    /// 会话结束 / 切书 / 签名变化即调用（合规禁令第 4 条）。
    public func invalidateAll() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll(keepingCapacity: false)
    }
}
