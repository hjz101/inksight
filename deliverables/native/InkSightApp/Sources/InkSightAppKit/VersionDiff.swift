import Foundation
import InkSightCore

// MARK: - VersionDiff（FR-018 版本对比）

/// 版本对比结果：按章给出「相同 / 有差异 / 仅一侧存在」。
///
/// 用途：「换一个版本」面板的次入口「版本对比」——让用户在切换前知道
/// **两个副本差在哪**（而不是盲换）。
///
/// 判据轻量：**章节指纹（归一化后的 FNV-1a 64）**比较，
/// 不做逐字 diff（那是编辑器的活，且长书全文 diff 会爆内存）。
public enum VersionDiff {

    /// 单章对比状态。
    public enum ChapterState: String, Equatable, Sendable {
        /// 两侧都存在且指纹相同
        case identical
        /// 两侧都存在但内容不同
        case different
        /// 只在左侧（当前版本）存在
        case leftOnly
        /// 只在右侧（候选版本）存在
        case rightOnly

        public var displayText: String {
            switch self {
            case .identical: return "一致"
            case .different: return "有差异"
            case .leftOnly:  return "仅当前版本"
            case .rightOnly: return "仅候选版本"
            }
        }
    }

    /// 单章对比条目。
    public struct ChapterDiff: Equatable, Sendable {
        public let chapterIndex: Int
        public let state: ChapterState
        public init(chapterIndex: Int, state: ChapterState) {
            self.chapterIndex = chapterIndex
            self.state = state
        }
    }

    /// 对比报告。
    public struct Report: Equatable, Sendable {
        public let chapters: [ChapterDiff]

        /// 汇总（用于面板顶部一行文案）。
        public var summary: String {
            let identical = chapters.filter { $0.state == .identical }.count
            let different = chapters.filter { $0.state == .different }.count
            let leftOnly = chapters.filter { $0.state == .leftOnly }.count
            let rightOnly = chapters.filter { $0.state == .rightOnly }.count
            var parts: [String] = ["共 \(chapters.count) 章"]
            if identical > 0 { parts.append("一致 \(identical)") }
            if different > 0 { parts.append("有差异 \(different)") }
            if leftOnly > 0 { parts.append("仅当前 \(leftOnly)") }
            if rightOnly > 0 { parts.append("仅候选 \(rightOnly)") }
            return parts.joined(separator: " · ")
        }

        /// 是否存在差异（无差异时面板显示"两个版本内容一致"）。
        public var hasDifferences: Bool {
            chapters.contains { $0.state != .identical }
        }
    }

    /// 对比两个副本的同章文本。
    ///
    /// - Parameters:
    ///   - left: 当前版本的章节文本（按章序）。
    ///   - right: 候选版本的章节文本（按章序）。
    /// - Returns: 逐章对比报告（章数以较多一侧为准）。
    public static func compare(left: [String], right: [String]) -> Report {
        let count = max(left.count, right.count)
        var diffs: [ChapterDiff] = []
        diffs.reserveCapacity(count)
        for i in 0..<count {
            let l = i < left.count ? left[i] : nil
            let r = i < right.count ? right[i] : nil
            let state: ChapterState
            switch (l, r) {
            case let (.some(a), .some(b)):
                state = fingerprint(a) == fingerprint(b) ? .identical : .different
            case (.some, .none):
                state = .leftOnly
            case (.none, .some):
                state = .rightOnly
            case (.none, .none):
                continue
            }
            diffs.append(ChapterDiff(chapterIndex: i, state: state))
        }
        return Report(chapters: diffs)
    }

    /// 章节指纹：归一化（去空白/标点）后 FNV-1a 64（与领域内指纹同源）。
    static func fingerprint(_ text: String) -> UInt64 {
        Fingerprint.fnv1a64(VersionAlignmentEngine.normalize(text))
    }
}
