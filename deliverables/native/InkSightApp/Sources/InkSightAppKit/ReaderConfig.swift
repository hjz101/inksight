import Foundation

// MARK: - 翻页交互配置（FR-008 五式翻页；NFR-02 / NFR-06 标注待真机 POC-5）

/// 翻页方式（FR-008）：五式可切换，由可读配置驱动；默认 `scroll`。
///
/// 说明（派单原口径）：
/// - NFR-02 帧率（59fps+ / 118fps+）属**逻辑接入、标注待真机 POC-5**——本包只落地
///   切换机制与分页容器，不在此伪造帧率实测；
/// - `curl` / `flip` 的真实转场动画（UIPageViewController.pageCurl 等）在真机 POC-5 校准，
///   本包用 SwiftUI 等价分页容器承载，保证 macOS 测试构建与 iOS 同构可编译。
public enum PageTurnMode: String, CaseIterable, Codable, Sendable {
    /// 不翻页：单页静态展示（用于「无动画」对照 / 无障碍偏好）。
    case none
    /// 横向滚动翻页（默认）。
    case scroll
    /// 纵向滚动翻页。
    case vertical
    /// 翻页式（左右硬切，POC-5 校准真实转场）。
    case flip
    /// 卷曲式（pageCurl，POC-5 校准真实转场）。
    case curl

    /// 人类可读名称（展示用）。
    public var displayName: String {
        switch self {
        case .none:    return "无翻页"
        case .scroll:  return "横向滚动"
        case .vertical: return "纵向滚动"
        case .flip:    return "翻页"
        case .curl:    return "卷曲"
        }
    }
}

/// 阅读器配置（单一来源的可读配置）。
///
/// NFR-06（停止 CADisplayLink）：本包不引入常驻渲染循环——翻页交互交由 SwiftUI 的分页容器
/// 在交互期间才绘制、空闲即不重绘，故「空闲停止渲染」由框架同构保证；显式 `CADisplayLink`
/// 值守（若 POC-5 接入自定义转场动画时）须在空闲 `idleDisplayLinkStopSeconds` 秒后停摆，
/// 此常量为该纪律的锚点。
public struct ReaderConfig: Sendable {
    /// 当前翻页方式（FR-008）。
    public var pageTurnMode: PageTurnMode
    /// NFR-06：空闲多少秒后停止渲染循环（CADisplayLink 值守口径）。
    public let idleDisplayLinkStopSeconds: Double
    /// 进度回写防抖（页/滚动停止后多少秒落盘）。
    public let progressWriteDebounceSeconds: Double

    public init(pageTurnMode: PageTurnMode = .scroll,
                idleDisplayLinkStopSeconds: Double = 3,
                progressWriteDebounceSeconds: Double = 0.5) {
        self.pageTurnMode = pageTurnMode
        self.idleDisplayLinkStopSeconds = idleDisplayLinkStopSeconds
        self.progressWriteDebounceSeconds = progressWriteDebounceSeconds
    }

    /// 默认配置：横向滚动翻页（派单「default none or scroll, TBD POC-5」取 scroll）。
    public static let `default` = ReaderConfig()
}
