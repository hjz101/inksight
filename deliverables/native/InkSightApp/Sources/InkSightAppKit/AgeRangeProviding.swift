import Foundation
import SwiftUI

// MARK: - AgeRangeProviding（FR-032 DeclaredAgeRange 注入点）

/// 系统分龄声明的抽象（FR-032 ①：`DeclaredAgeRange`，iOS 26+）。
///
/// 契约（PRD FR-032 原文）：
/// - 首启用 `AgeRangeService.shared.requestAgeRange(ageGates:)`；
/// - 系统返回 `.sharing(AgeRange{lowerBound, upperBound, ageRangeDeclaration})`
///   或 `.declinedSharing`；
/// - **只申请 1 个 gate = 18**（最小必要）；
/// - **不自建「选 18+ 就放行」的假门**。
///
/// 本类型是**注入点**：真机实现由 App 层用系统 API 提供；测试用 Mock。
/// 映射规则（`AgeGateState` 派生）集中在 `AgeGateState.from(declaration:)`，
/// 保证「系统答案 → 四态」只有一处判定。
public enum AgeRangeDeclaration: Equatable, Sendable {
    /// 用户共享了年龄段（`upperBound` 为 nil 表示"及以上"）。
    case sharing(lowerBound: Int, upperBound: Int?)
    /// 用户拒绝共享。
    case declined
    /// 系统不可用（旧系统 / API 失败）——按保守方向处理。
    case unavailable
}

/// 分龄声明提供者（注入点）。
public protocol AgeRangeProviding: Sendable {
    /// 请求系统分龄（只申请 gate=18）。
    func requestAgeRange() async -> AgeRangeDeclaration
}

// MARK: - AgeGateState 派生（系统答案 → 四态）

public extension AgeGateState {

    /// 由系统分龄声明派生四态（FR-032 ②：**禁止 `default: 放行`**）。
    ///
    /// 判定口径（保守方向：少保护是错误，虚假陈述是更重的错误）：
    /// - `.declined` → `.unverified`（用户拒答：在线能力不可用，非"放行"）；
    /// - `.unavailable` → `.unverified`（系统不可用：同样保守，**不假定成年**）；
    /// - `.sharing(lower, nil)` 且 `lower >= 18` → `.adultConfirmed`；
    /// - `.sharing(lower, upper)` 且 `upper <= 17` → `.minorConfirmed`（明确未成年人）；
    /// - 其余（跨 18 边界 / 下界 < 18 且上界未知）→ `.ageUnresolved`（**不可断定，套宵禁**）。
    static func from(_ declaration: AgeRangeDeclaration) -> AgeGateState {
        switch declaration {
        case .declined, .unavailable:
            return .unverified
        case .sharing(let lower, let upper):
            if let upper {
                if upper <= 17 { return .minorConfirmed }
                if lower >= 18 { return .adultConfirmed }
                // 跨 18 边界（如 16–20）：不可断定
                return .ageUnresolved
            }
            // 无上界：lower >= 18 才是成年；否则不可断定
            return lower >= 18 ? .adultConfirmed : .ageUnresolved
        }
    }
}

// MARK: - SystemDeclaredAgeRangeProvider（真机接入实现）

/// 系统 `DeclaredAgeRange` 实现（iOS 26+）。
///
/// **真机接入说明（如实登记）**：
/// - 系统 API 为 `AgeRangeService.shared.requestAgeRange(ageGates:)`（iOS 26+）；
/// - 本包为 Swift Package，**不保证系统符号在编译期可用**（不同 SDK/模拟器差异），
///   故用 `#if canImport(...)` + 运行时探测；不可用时返回 `.unavailable`
///   （由 `AgeGateState.from` 保守映射为 `.unverified`，**不假定成年**）。
/// - **真机验证待后续**（台账已登记）。
public struct SystemDeclaredAgeRangeProvider: AgeRangeProviding {

    /// 只申请一个 gate（FR-032：最小必要）。
    public static let requestedGate = 18

    public init() {}

    public func requestAgeRange() async -> AgeRangeDeclaration {
        #if canImport(AgeRangeService)
        // 真机路径（iOS 26+）：系统标准 sheet，用户共享或拒绝。
        // 具体调用封装在 App 层宿主（需 UIKit 生命周期），此处保留注入协议。
        return .unavailable
        #else
        // 当前 SDK 未提供该系统模块：诚实返回 unavailable（→ .unverified，保守）
        return .unavailable
        #endif
    }
}

// MARK: - MockAgeRangeProvider（测试/预览用）

/// 固定答案的注入实现（测试与原型演示用；**不得用于发行默认放行**）。
public struct MockAgeRangeProvider: AgeRangeProviding {
    private let declaration: AgeRangeDeclaration

    public init(_ declaration: AgeRangeDeclaration) {
        self.declaration = declaration
    }

    public func requestAgeRange() async -> AgeRangeDeclaration { declaration }
}
