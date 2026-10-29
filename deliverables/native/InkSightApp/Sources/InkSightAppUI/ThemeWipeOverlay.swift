import SwiftUI
import InkSightAppKit

// MARK: - ThemeWipeTransition（FR-028 第 ④ 项：主题切换转场配色）

/// 主题色带漫延（DESIGN §4.1 T3 `themeWipe`）。
///
/// 规格（原文逐条）：
/// - **420ms** `--e-band`；
/// - **径向 clip-path 裁剪**（禁写"渐变染色"——那不是本动效）；
/// - 色带层为**纯色渐变、不是玻璃**（玻璃层在这里会破 NFR-06）。
///
/// 用途：切换主题皮肤时覆盖全屏的转场层，配色取 `ThemeSkinSpec.Spec`
/// 的 `transitionFromHex → transitionToHex`（第 ④ 项「转场配色随主题变」）。
public struct ThemeWipeOverlay: View {
    /// 转场配色（起 → 止），来自皮肤规格。
    public let fromHex: String
    public let toHex: String
    /// 进度 0…1（由调用方驱动动画）。
    public var progress: Double = 0

    public init(fromHex: String, toHex: String, progress: Double = 0) {
        self.fromHex = fromHex
        self.toHex = toHex
        self.progress = progress
    }

    /// 动效时长（DESIGN 原文 420ms）。
    public static let duration: TimeInterval = 0.42

    public var body: some View {
        GeometryReader { geo in
            // 径向裁剪半径：从 0 扩到覆盖全屏对角
            let maxRadius = hypot(geo.size.width, geo.size.height)
            let radius = maxRadius * progress
            LinearGradient(colors: [Color(hexString: fromHex), Color(hexString: toHex)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .clipShape(
                    Circle()
                        .path(in: CGRect(x: geo.size.width / 2 - radius,
                                         y: geo.size.height / 2 - radius,
                                         width: radius * 2, height: radius * 2))
                )
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

// MARK: - ThemeWipeController（切换主题时的转场驱动）

/// 主题切换转场控制器（FR-028 第 ④ 项）。
///
/// **纪律**：转场期间只动 `opacity`/`transform`/裁剪半径，**不插值材质参数**
/// （DESIGN §2.5 通用规则）；色带层是**纯色渐变**，不经 `GlassSurface`。
@MainActor
public final class ThemeWipeController: ObservableObject {

    public static let shared = ThemeWipeController()

    @Published public private(set) var isAnimating = false
    @Published public private(set) var progress: Double = 0
    @Published public private(set) var fromHex: String = "#B8452F"
    @Published public private(set) var toHex: String = "#E8A38F"

    /// 开始一次主题转场（420ms）。
    ///
    /// - Parameter spec: 目标皮肤规格（取 `transitionFromHex/ToHex`）。
    public func wipe(to spec: ThemeSkinSpec.Spec) {
        fromHex = spec.transitionFromHex
        toHex = spec.transitionToHex
        isAnimating = true
        progress = 0
        withAnimation(.easeInOut(duration: ThemeWipeOverlay.duration)) {
            progress = 1
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(ThemeWipeOverlay.duration))
            isAnimating = false
            progress = 0
        }
    }
}
