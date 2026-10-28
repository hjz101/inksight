import Foundation

// MARK: - CopyrightComplaint（FR-033 版权声明与投诉通道）

/// 版权投诉模型（FR-033 P0 合规基座）。
///
/// 与原型 `contactSheet` 逐项对应（口径单一来源）：
/// - 投诉通达邮箱：`[TBD-CONTACT]` 占位（发布闸门 A9/A10，发行前必须替换为真实邮箱）。
/// - 受理回执：收到投诉后 **48 小时内**发出。
/// - 处理结果：**15 个工作日内**得出并答复。
/// - 重复侵权：同一权利人同一站点重复侵权达 **3 条**且指名同一具体章节 → 下架全部章节。
/// - 需齐备材料：①权利人主体信息 ②权属证明 ③指名侵权具体章节的 URL ④善意使用声明。
/// - **拒绝受理**：带凭据的规则文件（Token/Cookie/Authorization）、无具体段落定位的概括性主张。
public struct CopyrightComplaint: Equatable, Sendable {
    /// 投诉通达邮箱（占位；发行前必须替换，发布闸门 A9/A10 不可豁免）。
    public static let contactEmail = "[TBD-CONTACT]"

    /// 受理回执时限（小时）。
    public static let acknowledgmentHours = 48
    /// 处理结果时限（工作日）。
    public static let resolutionWorkdays = 15
    /// 重复侵权触发下架条数。
    public static let repeatInfringementThreshold = 3

    public let rightsHolder: String          // ①权利人主体信息
    public let proofOfOwnership: String      // ②权属证明
    public let infringingURL: String         // ③指名侵权具体章节的 URL
    public let goodFaithStatement: String    // ④善意使用声明

    public init(rightsHolder: String, proofOfOwnership: String,
                infringingURL: String, goodFaithStatement: String) {
        self.rightsHolder = rightsHolder
        self.proofOfOwnership = proofOfOwnership
        self.infringingURL = infringingURL
        self.goodFaithStatement = goodFaithStatement
    }

    /// 表单校验（FR-033 需齐备材料；返回缺失项，空数组 = 通过）。
    ///
    /// 判据（原型口径）：拒绝受理「Token、Cookie、Authorization 等带凭据的规则文件」
    /// 与「无具体段落定位的概括性主张」（如「整本全篇侵权」）。
    public var validationErrors: [String] {
        var errors: [String] = []
        if rightsHolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("权利人主体信息必填")
        }
        if proofOfOwnership.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("权属证明必填")
        }
        if infringingURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("侵权章节 URL 必填")
        } else if !infringingURL.lowercased().hasPrefix("http://")
                    && !infringingURL.lowercased().hasPrefix("https://") {
            errors.append("侵权章节 URL 须以 http(s):// 开头")
        }
        if goodFaithStatement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("善意使用声明必填")
        }
        return errors
    }
}

/// 投诉受理状态（FR-033 处置承诺留痕）。
public enum ComplaintDisposition: Equatable, Sendable {
    case pendingAcknowledgment      // 已收到，48h 内发出回执
    case acknowledged               // 已发出受理回执
    case resolved(Date)             // 已处理并答复
}
