import SwiftUI
import InkSightAppKit
import InkSightCore

// MARK: - ReaderSettingsSheet（FR-014 阅读设置浮层）

/// 阅读设置浮层（`setSheet` 的原生对应，L3 玻璃白名单成员）。
///
/// **FR-014 自绘浮层四条可用性（P0 逐条实现）**：
/// 1. **44pt 关闭按钮**（触控最小尺寸）；
/// 2. **`accessibilityAction(.escape)`**（无障碍"关闭"动作，VoiceOver 双指 Z 手势可触发）；
/// 3. **36×4pt 把手**（可下拉关闭的视觉抓手）；
/// 4. **scrim 点击关闭**（点遮罩空白处即关）。
///
/// 玻璃纪律：本浮层是 D-28 白名单「浮层与工具栏」成员，可用 L3；
/// `presentation` 支持 FR-014 四态（转场/手势时降级纯色+描边）。
struct ReaderSettingsSheet: View {
    /// 排版预设（双向绑定，改动即时落盘由调用方处理）。
    @Binding var preset: ReaderTypography
    /// 主题状态（FR-010）。
    @Binding var theme: ThemeState
    /// 四态收起（FR-014）。
    var presentation: GlassPresentationState = .steady
    /// 关闭回调（四种关闭方式共用同一入口）。
    var onClose: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            // ④ scrim 点击关闭
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { onClose() }
                .accessibilityLabel("关闭阅读设置")

            // 底部浮层（L3 玻璃）
            GlassSurface(strength: .l3, interactive: true,
                         cornerRadius: 22, presentation: presentation) {
                VStack(spacing: 0) {
                    // ③ 36×4pt 把手
                    Capsule()
                        .fill(Color.secondary.opacity(0.45))
                        .frame(width: 36, height: 4)
                        .padding(.top, 10)
                        .padding(.bottom, 6)
                        .accessibilityHidden(true)

                    // ① 44pt 关闭按钮
                    HStack {
                        Text("阅读设置").font(.headline)
                        Spacer()
                        Button(action: onClose) {
                            ThemedInkIcon(.close, size: 17)
                                .frame(width: 44, height: 44)   // 44pt 触控目标
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("关闭阅读设置")
                        .accessibilityAction(.escape) { onClose() }   // ② 无障碍"关闭"
                    }
                    .padding(.horizontal, 20)

                    settingsContent
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityAction(.escape) { onClose() }
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 字号（FR-009 档位制）
            tierRow("字号") {
                ForEach(TypographyTiers.fontSizes, id: \.self) { size in
                    tierChip("\(Int(size))", active: preset.fontSize == size) {
                        preset.fontSize = size
                        if preset.indent > 0 { preset.indent = size * 2 }
                    }
                }
            }
            // 行高
            tierRow("行高") {
                ForEach(TypographyTiers.lineHeights, id: \.self) { lh in
                    tierChip(String(format: "%.2f", lh),
                             active: preset.lineHeightMultiplier == lh) {
                        preset.lineHeightMultiplier = lh
                    }
                }
            }
            // 边距
            tierRow("边距") {
                ForEach(TypographyTiers.margins, id: \.self) { m in
                    tierChip("\(Int(m))", active: preset.insets.leading == m) {
                        preset.insets.leading = m
                        preset.insets.trailing = m
                    }
                }
            }
            // 主题（FR-010）
            tierRow("主题") {
                tierChip("雪纸", active: theme.skin == .snowPaper) {
                    theme.skin = .snowPaper
                }
                tierChip("夜航", active: theme.skin == .nightVoyage) {
                    theme.skin = .nightVoyage
                }
            }
        }
        .padding(.top, 8)
    }

    private func tierRow<C: View>(_ title: String, @ViewBuilder chips: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) { chips() }
        }
    }

    private func tierChip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: active ? .semibold : .regular))
                .frame(minWidth: 56, minHeight: 36)
                .background(active ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05),
                            in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}
