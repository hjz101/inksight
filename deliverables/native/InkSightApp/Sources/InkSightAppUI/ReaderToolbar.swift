import SwiftUI
import InkSightAppKit

// MARK: - ReaderToolbar（FR-014 阅读底部工具条）

/// 阅读底部工具条（DESIGN §5 ④：阅读工具条 L1，合计 1 组玻璃）。
///
/// 纪律：
/// - **玻璃白名单成员**：阅读工具条是 D-28 白名单「浮层与工具栏」允许的玻璃；
/// - **FR-014 四态收起**：`presentation` 为 `scrolling`/`gesture` 时自动降为
///   半透明纯色 + 1pt 描边（DESIGN §2.5），结束后 120ms 淡回完整玻璃；
/// - **恒含「书签」入口**（FR-011 联动：EGG4 关态时折角不注册，加书签走本入口）；
/// - **正文区 0 玻璃不破**：本工具条是阅读器 chrome 层（浮层），不是正文容器。
struct ReaderToolbar: View {
    /// 四态收起（FR-014）：由上层按翻页/滚动状态驱动。
    var presentation: GlassPresentationState = .steady
    /// FR-028：主题玻璃 tint（第 ③ 项，随主题联动）。
    var themeTint: (hex: String, opacity: Double)? = nil
    /// FR-028：主题圆角偏移（蜜桃汽水 +4；DESIGN §3.1 token `radius-shift`）。
    var radiusShift: Double = 0
    /// 加书签回调（FR-011）。
    var onBookmark: () -> Void = {}
    /// 打开「换一个版本」面板（FR-018 主路径）。
    var onSwapVersion: () -> Void = {}
    /// 打开阅读设置浮层（`setSheet` 原生对应）。
    var onSettings: () -> Void = {}
    /// 打开目录（按章节锚点跳转）。
    var onTOC: () -> Void = {}
    /// 打开进度（显示当前章节/页位置并可定位）。
    var onProgress: () -> Void = {}
    /// FR-012 朗读面板。
    var onTTS: () -> Void = {}
    var body: some View {
        GlassSurface(strength: .l1, interactive: true,
                     // FR-028 token `radius-shift`：蜜桃汽水全站圆角 +4，不得硬编码
                     cornerRadius: 18 + CGFloat(radiusShift),
                     presentation: presentation,
                     themeTint: themeTint) {
            HStack(spacing: 4) {
                toolbarButton("目录", systemImage: "list.bullet", action: onTOC)
                toolbarButton("进度", systemImage: "book.pages", action: onProgress)
                toolbarButton("书签", systemImage: "bookmark", action: onBookmark)
                toolbarButton("换一个版本", systemImage: "arrow.triangle.swap", action: onSwapVersion)
                toolbarButton("排版", systemImage: "textformat.size", action: onSettings)
                toolbarButton("朗读", systemImage: "waveform", action: onTTS)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 52)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func toolbarButton(_ label: String,
                               systemImage: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 17))
                Text(label)
                    .font(.system(size: 10))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
