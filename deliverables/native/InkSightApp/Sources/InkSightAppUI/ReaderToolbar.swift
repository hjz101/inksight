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
    /// 加书签回调（FR-011）。
    var onBookmark: () -> Void = {}
    /// 打开「换一个版本」面板（FR-018 主路径）。
    var onSwapVersion: () -> Void = {}
    /// 打开阅读设置浮层（`setSheet` 原生对应）。
    var onSettings: () -> Void = {}

    var body: some View {
        GlassSurface(strength: .l1, interactive: true,
                     cornerRadius: 18, presentation: presentation) {
            HStack(spacing: 4) {
                toolbarButton("目录", systemImage: "list.bullet", action: {})
                toolbarButton("进度", systemImage: "book.pages", action: {})
                toolbarButton("书签", systemImage: "bookmark", action: onBookmark)
                toolbarButton("换一个版本", systemImage: "arrow.triangle.swap", action: onSwapVersion)
                toolbarButton("排版", systemImage: "textformat.size", action: onSettings)
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
