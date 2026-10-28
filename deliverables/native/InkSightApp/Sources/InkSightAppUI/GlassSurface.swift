import SwiftUI
import InkSightAppKit

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

    /// - Parameters:
    ///   - strength: 玻璃强度 L1/L2/L3（tint 0.14/0.20/0.28——**仅 tint 强度，非材质切换**）。
    ///   - interactive: 按控件性质单独判定（按钮/可点卡片 true；静态容器/Toast false）。
    ///     **`.interactive()` 与档位正交**——L1 容器＋不可点＝无按压回弹（Toast 反例）。
    init(strength: GlassStrength, interactive: Bool = false,
         cornerRadius: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.strength = strength
        self.interactive = interactive
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        // GlassEffectContainer：共享采样域（同一视觉区域多个玻璃必须同容器，
        // 否则每帧各自重算背景互采样——滚动闪烁与掉帧的根因）。
        // spacing 20 为设计默认值，**待 POC-2 真机校准回填**（融合阈值≠视觉间距）。
        GlassEffectContainer(spacing: GlassSpec.containerSpacing) {
            content
                .glassEffect(glass, in: .rect(cornerRadius: cornerRadius, style: .continuous))
        }
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
