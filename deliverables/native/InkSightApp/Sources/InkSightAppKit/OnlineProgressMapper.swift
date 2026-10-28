import Foundation
import InkSightCore

// MARK: - OnlineProgressMapper（FR-024b 在线进度映射）

/// 在线进度映射服务（FR-024b）：**只存章节号／标题／字符偏移／首尾指纹哈希**，
/// 表结构没有正文字段（`fr024b_mapping`），FTS 不索引在线正文。
///
/// 用途：换源／换版本后，用「首尾指纹」在目标章节里找回续读位置——
/// - 源侧：打开在线章时，把「章节号 + 标题 + 字符偏移 + 首尾指纹」落库（`upsertFR024b`）；
/// - 目标侧：切换后，用指纹匹配新章节，按 `charOffset` 恢复阅读位置。
///
/// **代价明确（技术约束清单原文）**：在线书不支持跨会话全文检索——
/// 检索范围＝本地 FTS ＋ 会话内存已加载章节（≤3 章），会话结束即销毁。
public struct OnlineProgressMapper {

    private let cache: SQLiteCache

    public init(cache: SQLiteCache) {
        self.cache = cache
    }

    /// 记录某本书某章的在线进度映射（幂等覆盖）。
    ///
    /// - Parameter bodyStart/bodyEnd: 章节正文首尾片段，用于计算指纹。
    ///   **只存指纹，不存正文**（FR-024b）。
    @discardableResult
    public func record(bookID: String, chapterID: Int, title: String,
                       charOffset: Int,
                       bodyStart: String, bodyEnd: String) -> Result<Void, SQLiteCacheError> {
        let mapping = FR024bMapping(chapterID: chapterID, title: title, charOffset: charOffset,
                                    startFingerprint: Fingerprint.fnv1a64(bodyStart),
                                    endFingerprint: Fingerprint.fnv1a64(bodyEnd))
        return cache.upsertFR024b(bookID: bookID, [mapping])
    }

    /// 按章节读取映射（续读定位入口）。
    public func mapping(bookID: String, chapterID: Int) -> FR024bMapping? {
        cache.loadFR024b(bookID: bookID, chapterID: chapterID)
    }

    /// 换源/换版本后对齐：给定目标章的首尾片段，找映射里指纹最匹配的一章，
    /// 返回「应恢复的字符偏移」。无匹配返回 nil（诚实：不强行对齐）。
    ///
    /// 判据：首指纹精确匹配优先；否则首/尾指纹任一匹配（容忍标题漂移）。
    public func align(bookID: String,
                      targetStart: String, targetEnd: String) -> Int? {
        let targetStartFP = Fingerprint.fnv1a64(targetStart)
        let targetEndFP = Fingerprint.fnv1a64(targetEnd)
        for m in cache.loadFR024b(bookID: bookID) {
            if m.startFingerprint == targetStartFP { return m.charOffset }
        }
        for m in cache.loadFR024b(bookID: bookID) {
            if m.endFingerprint == targetEndFP { return m.charOffset }
        }
        return nil
    }
}
