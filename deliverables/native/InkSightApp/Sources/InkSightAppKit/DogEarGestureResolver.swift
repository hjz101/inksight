import Foundation
import CoreGraphics

// MARK: - DogEarGestureResolver（EGG4 页角折角双判定）

/// 右下角双判定热区（DESIGN §5 ④ 规范正文，非仅验收）。
///
/// 契约（原文逐条）：
/// - 热区 **44×44pt**，位于**右下角**；该角**不留死区**；
/// - 按下 **<300ms 抬手 → 翻页**（与全屏右侧翻页一致）；
/// - 按住 **≥300ms → 折角跟手**，阈值处一次 `.light`；
/// - 松手 **>12pt → 吸附成静态折角并立即回写书签 + 再一次 `.light`**；
/// - 松手 **<12pt → 回弹，不加书签**（不写书签）。
///
/// 两次触感分工：一次宣告"进入折角"，一次宣告"书签已写"。
///
/// 本类型是**纯逻辑**（输入触摸时长/位移，输出判定），便于在无 UI 环境下测试。
public enum DogEarGestureResolver {

    /// 热区边长（pt）。
    public static let hotZoneSize: CGFloat = 44
    /// 长按阈值（秒）：≥ 此值进入折角跟手。
    ///
    /// **规范冲突（如实登记，D-87）**：PRD FR-030 EGG4 行写「长按页角 **400ms**」，
    /// DESIGN §5 ④「阅读器右下双判定热区（规范正文，不只放验收）」写「**≥300ms**」。
    /// 采纳 **300ms**，依据：
    /// 1. DESIGN 该节自述为「规范正文，不只放验收」，且是**双判定**的完整表述
    ///    （把 300ms 与"<300ms 翻页"绑成一对，改一个必然要改另一个）；
    /// 2. PRD 的 400ms 出现在 EGG4 注册表行，描述的是「折角彩蛋」的**单一动作**，
    ///    未涉及与翻页的分界；
    /// 3. 双判定是后出的、更细的规范，且**它才是决定"这角翻不翻页"的那一条**
    ///    （按 400ms 做会让 300–400ms 区间既非翻页也不进折角，形成手感死区）。
    /// 该冲突**不自行改 PRD**（PRD 是需求真源），已在台账 D-87 记为待需求方确认项。
    public static let holdThresholdSeconds: TimeInterval = 0.300
    /// 吸附阈值（pt）：松手位移 > 此值才吸附并写书签。
    public static let snapThresholdPoints: CGFloat = 12

    /// 手势阶段判定结果。
    public enum Outcome: Equatable, Sendable {
        /// 短按抬手 → 翻页（该角不留死区）
        case pageTurn
        /// 长按开始 → 折角跟手（触发一次 `.light` 宣告"进入折角"）
        case enterDogEar
        /// 长按松手且位移 >12pt → 吸附 + 写书签（再一次 `.light` 宣告"书签已写"）
        case snapAndBookmark
        /// 长按松手但位移 ≤12pt → 回弹，**不写书签**
        case springBack

        /// 是否应写书签（只有吸附才写）。
        public var writesBookmark: Bool { self == .snapAndBookmark }

        /// 应触发的触感次数（进入折角 1 次；吸附再 1 次，共 2 次）。
        public var hapticCount: Int {
            switch self {
            case .pageTurn:      return 0
            case .enterDogEar:   return 1
            case .snapAndBookmark: return 2   // 进入 1 次 + 书签 1 次
            case .springBack:    return 1     // 仅进入时那一次
            }
        }
    }

    /// 点是否落在右下角热区内。
    public static func isInHotZone(_ point: CGPoint, containerSize: CGSize) -> Bool {
        guard containerSize.width > 0, containerSize.height > 0 else { return false }
        let zoneMinX = containerSize.width - hotZoneSize
        let zoneMinY = containerSize.height - hotZoneSize
        return point.x >= zoneMinX && point.x <= containerSize.width
            && point.y >= zoneMinY && point.y <= containerSize.height
    }

    /// 抬手时判定（短按 → 翻页）。
    ///
    /// - Parameter pressDuration: 按下到抬手的时长（秒）。
    public static func resolveTap(pressDuration: TimeInterval) -> Outcome {
        pressDuration < holdThresholdSeconds ? .pageTurn : .enterDogEar
    }

    /// 长按后松手判定（按位移决定吸附或回弹）。
    ///
    /// - Parameter translation: 松手时相对按下点的位移（pt，取欧氏距离或纵向位移由调用方决定；
    ///   本实现取**纵向位移**——折角跟手是自上而下拉动）。
    public static func resolveRelease(verticalTranslation: CGFloat) -> Outcome {
        verticalTranslation > snapThresholdPoints ? .snapAndBookmark : .springBack
    }
}
