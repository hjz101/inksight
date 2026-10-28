import Foundation

// MARK: - Degradation（降级门面，总册第 6 章「三个门面」之三，台账 D-15）

/// 降级门面：**所有 fallback 必须经 `degrade(kind, declaresData:detail:)`**。
///
/// 门面的作用不是保证正确，是让"无意遗漏"变成"故意误报"——后者可追责。
/// 每个 `Kind` 必须在《降级申报清单》登记一行（本文件下部的 `registry` 即清单的代码镜像），
/// CI 单测遍历 `Degradation.Kind` 全枚举校验登记完整性（缺一行即该单测失败、CI 挡合并）。
///
/// 语义（见《降级申报清单》§二）：
/// - `declaresData == true`  ⇒ 降级路径会呈现内容数据（须写明数据来源类别）。
/// - `declaresData == false` ⇒ 降级路径只呈现状态与文案，不呈现任何内容数据。
/// - `unspecified` ⇒ 尚未判定，**不允许**，CI 视为未登记。
public enum Degradation {

    /// 降级种类。**新增 case 必须同步登记 `registry` 与《降级申报清单》**，
    /// 否则 `DegradationTests.testEveryKindIsRegistered` 失败、CI 挡合并。
    public enum Kind: String, CaseIterable, Sendable {
        case chapterLoadFailed
        case sourceAllUnavailable
        case importParseFailed
        case epubChapterMissing
        case alignmentFallback
        case fallbackToPlainText
        case offlineNoCache
        case searchNoResult
        case fontFallback
        case glassReduced

        /// 明确禁止的降级（清单 §四）——**不在 `Kind` 里**，从类型上杜绝。
        /// 这三个是"降级被当绕路口子"的反模式：跨版本自动补章、远端正文落盘、静默只显部分章节。
        /// 放在注释里而非枚举里，是因为**禁止的东西不该有名字**——有名字就有人会找它。
    }

    /// 数据声明：这次降级是否把内容摆在用户面前。
    public enum DeclaresData: Sendable {
        case yes(source: String)   // 呈现内容数据，须写明来源类别
        case no                    // 只呈现状态与文案
    }

    /// 清单登记项（《降级申报清单》§三的代码镜像）。
    public struct RegistryEntry: Sendable {
        public let kind: Kind
        public let declaresData: Bool
        public let dataSourceCategory: String?   // declaresData == true 时必填
        public let uiPresentation: String
    }

    /// 降级事件记录（可观测输出：让降级发生可被日志/测试看见）。
    public struct Event: Sendable {
        public let kind: Kind
        public let declaresData: Bool
        public let detail: String
        public let timestamp: Date
    }

    // MARK: - 清单（与《降级申报清单-墨见InkSight.md》§三逐行对应）

    /// 全登记表。CI 单测遍历 `Kind.allCases` 校验每个 kind 在此登记且 `declaresData` 一致。
    /// **新增 kind 必须：① 在此登记 ② 在《降级申报清单》登记 ③ 补单测**。
    public static let registry: [RegistryEntry] = [
        RegistryEntry(kind: .chapterLoadFailed, declaresData: false, dataSourceCategory: nil,
                      uiPresentation: "「本章加载失败」+ 原因 + 「重试」+「换一个版本」"),
        RegistryEntry(kind: .sourceAllUnavailable, declaresData: false, dataSourceCategory: nil,
                      uiPresentation: "「本书暂不可读」+ 已尝试的路径说明，不显示任何缓存正文"),
        RegistryEntry(kind: .importParseFailed, declaresData: false, dataSourceCategory: nil,
                      uiPresentation: "显示文件名与失败原因，不显示「失败」二字"),
        RegistryEntry(kind: .epubChapterMissing, declaresData: false, dataSourceCategory: nil,
                      uiPresentation: "目录页标记该章缺失并可跳过"),
        RegistryEntry(kind: .alignmentFallback, declaresData: true, dataSourceCategory: "用户本地文件",
                      uiPresentation: "明示「按位置近似对齐」，不静默"),
        RegistryEntry(kind: .fallbackToPlainText, declaresData: true, dataSourceCategory: "用户本地文件",
                      uiPresentation: "降级渲染，保留可读性"),
        RegistryEntry(kind: .offlineNoCache, declaresData: false, dataSourceCategory: nil,
                      uiPresentation: "「无本地副本」+ 引导导入，不得显示任何在线内容占位"),
        RegistryEntry(kind: .searchNoResult, declaresData: false, dataSourceCategory: nil,
                      uiPresentation: "「已查询 N 个源」+ 三条明确出路"),
        RegistryEntry(kind: .fontFallback, declaresData: false, dataSourceCategory: nil,
                      uiPresentation: "回退系统默认字体，正文照常呈现（非内容声明，故为 false）"),
        RegistryEntry(kind: .glassReduced, declaresData: false, dataSourceCategory: nil,
                      uiPresentation: "材质降一档或改纯色，布局不变"),
    ]

    /// 供 CI 单测：kind → 登记项。
    public static func entry(for kind: Kind) -> RegistryEntry? {
        registry.first { $0.kind == kind }
    }

    // MARK: - 唯一入口

    /// 降级校验错误（`degrade` 的失败路径）。
    ///
    /// 门面既要挡住误用，又要**可测**：用返回错误而非 `fatalError`，
    /// 让「谎报 declaresData」「未登记 kind」成为可被单测断言的状态——
    /// 否则门面本身的正确性无法验证（`fatalError` 在 XCTest 进程内不可捕获）。
    public enum DegradeError: Error, Equatable, Sendable {
        /// kind 未在《降级申报清单》登记。
        case unregistered(kind: Kind)
        /// declaresData 与清单登记不符（谎报可追责）。
        case mismatchedDeclaresData(kind: Kind, declared: Bool, registered: Bool)
    }

    /// **唯一降级入口**：任何 fallback 必须调用本方法。
    ///
    /// - 未登记的 kind → `.failure(.unregistered)`（开发期 bug，单测 `testEveryKindIsRegistered` 已挡）。
    /// - `declaresData` 与清单不符 → `.failure(.mismatchedDeclaresData)`（谎报可追责，清单 §二）。
    /// - 校验通过 → 返回降级事件（观测点：生产接入日志/遥测的统一出口，不进 UI 文案）。
    @discardableResult
    public static func degrade(kind: Kind, declaresData: Bool,
                               detail: String) -> Result<Event, DegradeError> {
        guard let entry = entry(for: kind) else {
            return .failure(.unregistered(kind: kind))
        }
        guard entry.declaresData == declaresData else {
            return .failure(.mismatchedDeclaresData(kind: kind,
                                                    declared: declaresData,
                                                    registered: entry.declaresData))
        }
        let event = Event(kind: kind, declaresData: declaresData, detail: detail, timestamp: Date())
        // 观测点：生产接入日志/遥测时在此统一出口（不进 UI 文案，保持单一来源）。
        return .success(event)
    }
}
