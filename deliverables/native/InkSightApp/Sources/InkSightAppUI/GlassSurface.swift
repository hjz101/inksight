import SwiftUI
import InkSightAppKit

// MARK: - GlassPresentationState（FR-014 玻璃四态）

/// 玻璃容器的运行时表现状态（DESIGN §2.5 四态收起）。
///
/// - `steady`：静止，使用完整玻璃；
/// - `scrolling`：滚动/翻页中，降为半透明纯色 + 1pt 描边；
/// - `transition`：380ms 转场，仅容许 opacity/transform，玻璃材质参数冻结；
/// - `gesture`：手势跟手，降为半透明纯色 + 1pt 描边。
///
/// `transition` 保持玻璃材质不变（不插值 tint/blur/refraction）；
/// `scrolling`/`gesture` 切换纯色，动作结束 120ms 后恢复完整玻璃。
enum GlassPresentationState: Equatable {
    case steady
    case scrolling
    case transition
    case gesture

    /// 是否绘制完整 Liquid Glass（transition 期间材质冻结，故仍为 true）。
    var usesGlass: Bool { self == .steady || self == .transition }

    /// 是否绘制降级态（纯色 + 1pt 描边）。
    var usesOpaqueFallback: Bool { self == .scrolling || self == .gesture }

    /// 恢复完整材质的淡入时长（DESIGN §2.5：120ms）。
    static let restoreDuration: TimeInterval = 0.12

    /// 转场材质冻结时长（DESIGN §2.5：380ms）。
    static let transitionDuration: TimeInterval = 0.38
}

// MARK: - GlassSurface（唯一玻璃入口，观感等价、结构克制）

/// **全 App 唯一玻璃入口**（D-28 白名单 5 类容器专用：`setSheet` / `srcSheet` / `ageSheet` /
/// `contactSheet` / 主题商店预览卡·成就卡片）。
///
/// 结构克制三原则：
/// 1. **正文区 0 玻璃由结构保证**：阅读正文容器（`ReaderSurfaceView`）不引用本类型、
///    不暴露任何玻璃修饰入口——玻璃只能经由 `GlassSurface` 进入，而正文视图的公开 API
///    与 body 均不出现它（见 ReaderSurface.swift 说明）。
/// 2. **interactive 与 tint 正交**：interactive 由"控件是否可点击"决定，不随档位
///    （Toast 不可点却带回弹＝骗用户去点）。
/// 3. **单块 30% 面积兜底只适用屏内卡片类**；底部 sheet 类走高度 ≤639pt 口径（D-38），
///    由 `BottomSheetContainer` 承载，本类型不管面积。
struct GlassSurface<Content: View>: View {

    let content: Content
    let strength: GlassStrength
    let interactive: Bool
    let cornerRadius: CGFloat
    /// FR-014 四态收起：`steady`（全玻璃）/ `scrolling`（纯色+描边）/
    /// `transition`（材质冻结）/ `gesture`（纯色+描边）。默认 `steady`。
    var presentation: GlassPresentationState = .steady

    /// - Parameters:
    ///   - strength: 玻璃强度 L1/L2/L3（tint 0.14/0.20/0.28——**仅 tint 强度，非材质切换**）。
    ///   - interactive: 按控件性质单独判定（按钮/可点卡片 true；静态容器/Toast false）。
    ///     **`.interactive()` 与档位正交**——L1 容器＋不可点＝无按压回弹（Toast 反例）。
    ///   - presentation: FR-014 四态（默认稳态）。
    init(strength: GlassStrength, interactive: Bool = false,
         cornerRadius: CGFloat = 20,
         presentation: GlassPresentationState = .steady,
         @ViewBuilder content: () -> Content) {
        self.content = content()
        self.strength = strength
        self.interactive = interactive
        self.cornerRadius = cornerRadius
        self.presentation = presentation
    }

    var body: some View {
        Group {
            if presentation.usesOpaqueFallback {
                // **降级态（DESIGN §2.5）**：纯色 + 1pt 描边——滚动中/手势跟手，
                // 不采样 backdrop（避免动效帧里全屏重算）。结束后 120ms 淡回完整玻璃。
                content
                    .background(fallbackColor, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
                    .transition(.opacity)
            } else {
                // 稳态 / 转场（材质冻结）：完整 Liquid Glass
                GlassEffectContainer(spacing: GlassSpec.containerSpacing) {
                    content
                        .glassEffect(glass, in: .rect(cornerRadius: cornerRadius, style: .continuous))
                }
            }
        }
        .animation(.easeOut(duration: GlassPresentationState.restoreDuration),
                   value: presentation.usesOpaqueFallback)
    }

    /// 降级态底色：半透明纯色（`rgba(surface,.92)`，DESIGN §2.5）。
    /// 用 `.background` 语义色近似纸面（跨平台；阅读器工具条由调用方传主题纸面色）。
    private var fallbackColor: Color {
        Color.gray.opacity(0.92)
    }

    /// 降级态描边（DESIGN §2.4：降级态必须 1pt 描边）。
    private var borderColor: Color {
        Color.primary.opacity(0.06)
    }

    /// kern 同款教训：**参数与档位正交**，不在档位表里混列（L1 加/L2 不加会制造假相关）。
    private var glass: Glass {
        let base = Glass.regular.tint(.primary.opacity(strength.tintOpacity))
        return interactive ? base.interactive() : base
    }
}

// MARK: - BottomSheetContainer（D-38 高度口径）

/// 底部 sheet 类容器：**高度 ≤ 屏高 75%（639pt）＋ 内部滚动**，不外溢、不裁切、不删内容（D-38）。
/// 内容完整性优先于面积上限（信息承载类）；单块 30% 兜底不适用（那是屏内卡片类的尺子）。
struct BottomSheetContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            let maxHeight = min(GlassSpec.bottomSheetMaxHeight, geo.size.height * 0.75)
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: maxHeight)
            .frame(maxWidth: .infinity)
        }
    }
}
