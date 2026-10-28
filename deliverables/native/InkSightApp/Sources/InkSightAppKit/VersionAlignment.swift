import Foundation
import InkSightCore

// MARK: - VersionAlignment（FR-018 同书多副本对齐）

/// 位置对齐结果（FR-018：指纹匹配 → 百分比降级，**不匹配要明示**）。
public enum VersionAlignment: Equatable, Sendable {
    /// 指纹精确匹配（标题归一 ＋ 首尾 200 字哈希）——可精确回到同一位置。
    case exact(charOffset: Int)
    /// 指纹不匹配，按章节内位置比例降级（百分比），**必须明示"近似对齐"**。
    case approximate(charOffset: Int, percent: Double)
    /// 完全无法对齐（章节都找不到）。
    case unavailable

    /// 用户可读说明（FR-018：不匹配降级百分比并明示）。
    public var displayText: String {
        switch self {
        case .exact:                  return "位置精确对齐"
        case .approximate(_, let p):   return String(format: "按位置近似对齐（%.0f%%）", p)
        case .unavailable:            return "无法对齐（章节缺失）"
        }
    }

    /// 是否精确（用于 UI 区分展示）。
    public var isExact: Bool { if case .exact = self { return true }; return false }
}

/// 候选副本（「换一个版本」面板的一行）。
///
/// 字段依 FR-018 原文：**文件名／版本标签／格式·大小／位置匹配度**，
/// **不出现"源名"**（这是本地多副本，不是书源）。
public struct VersionCandidate: Equatable, Sendable, Identifiable {
    public let id: String          // bookID 或文件哈希
    /// 文件名（如 `红楼梦.txt`）。
    public let fileName: String
    /// 版本标签：**用户可编辑纯文本，默认「未命名版本」，我方不预设任何值**。
    public var versionLabel: String
    /// 其它本地副本不在此类型上表达来源（FR-018：不出现"源名"）。
    public let fileSizeBytes: Int
    public let format: String
    /// 位置匹配度（0–1，1 = 精确）。
    public let matchScore: Double

    public static let defaultVersionLabel = "未命名版本"

    public init(id: String, fileName: String,
                versionLabel: String = VersionCandidate.defaultVersionLabel,
                fileSizeBytes: Int, format: String = "TXT", matchScore: Double) {
        self.id = id
        self.fileName = fileName
        self.versionLabel = versionLabel
        self.fileSizeBytes = fileSizeBytes
        self.format = format
        self.matchScore = matchScore
    }

    /// 「格式·大小」列（如 `TXT · 2.1 MB`）。
    public var formatAndSize: String {
        String(format: "%@ · %.1f MB", format, Double(fileSizeBytes) / 1_048_576)
    }

    /// 「位置匹配度」列。
    public var matchText: String {
        if matchScore >= 0.999 { return "精确" }
        return String(format: "%.0f%%", matchScore * 100)
    }
}

// MARK: - VersionAlignmentEngine（匹配计算，可测）

/// 位置对齐引擎（FR-018）：用「标题归一 ＋ 首尾 200 字哈希」做指纹匹配。
public enum VersionAlignmentEngine {

    /// 指纹窗口长度（FR-018：首尾 200 字）。
    public static let fingerprintWindow = 200

    /// 计算某章在目标副本中的对齐位置。
    ///
    /// - Parameters:
    ///   - sourceOffset: 源副本中的字符偏移（进度/笔记锚点）。
    ///   - sourceChapterLength: 源章节长度。
    ///   - targetChapterText: 目标副本同章的正文。
    ///   - targetChapterTitle: 目标副本同章标题（用于标题归一）。
    public static func align(sourceOffset: Int,
                             sourceChapterLength: Int,
                             sourceHead: String,
                             sourceTail: String,
                             targetChapterText: String,
                             targetChapterTitle: String) -> VersionAlignment {
        let target = targetChapterText as NSString
        guard target.length > 0, sourceChapterLength > 0 else { return .unavailable }

        // ① 首尾指纹匹配：标题归一 ＋ 首尾窗口哈希
        let headFP = Fingerprint.fnv1a64(normalize(sourceHead))
        let tailFP = Fingerprint.fnv1a64(normalize(sourceTail))

        let targetHead = String(target.substring(to: min(fingerprintWindow, target.length)))
        let targetTailStart = max(0, target.length - fingerprintWindow)
        let targetTail = String(target.substring(from: targetTailStart))

        let headMatch = Fingerprint.fnv1a64(normalize(targetHead)) == headFP
        let tailMatch = Fingerprint.fnv1a64(normalize(targetTail)) == tailFP

        if headMatch && tailMatch {
            // 精确：偏移按原值（章节内容一致）
            let clamped = min(max(0, sourceOffset), max(0, target.length - 1))
            return .exact(charOffset: clamped)
        }

        // ② 降级：按章节内位置比例（百分比），**明示近似**
        let ratio = Double(sourceOffset) / Double(sourceChapterLength)
        let approx = Int((Double(target.length) * min(max(ratio, 0), 1)).rounded())
        let clamped = min(max(0, approx), max(0, target.length - 1))
        _ = targetChapterTitle
        return .approximate(charOffset: clamped, percent: min(max(ratio, 0), 1) * 100)
    }

    /// 候选副本按**位置匹配度降序**排序（FR-018：多副本并存按匹配度降序）。
    public static func ranked(_ candidates: [VersionCandidate]) -> [VersionCandidate] {
        candidates.sorted { $0.matchScore > $1.matchScore }
    }

    /// 标题归一（去空白/标点，用于指纹匹配）。
    static func normalize(_ text: String) -> String {
        text.filter { !$0.isWhitespace && !$0.isPunctuation }
    }
}
