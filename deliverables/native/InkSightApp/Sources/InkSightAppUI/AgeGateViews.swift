import SwiftUI
import InkSightAppKit

// MARK: - 年龄状态条（视图层只读矩阵，禁止 if state == .xxx 拼文案）

/// 三态状态条：banner 文案由 `AgeGateMatrix.bannerText(state:variant:)` 派生（AGE_MATRIX §2 唯一来源）。
/// `.adultConfirmed` → nil → 状态条**结构上不生成**（不是隐藏）。
struct AgeStateBar: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.12))
    }
}

// MARK: - 拦截页（curtain）：标题由 banner 键派生（不变式 6），条目数 2／1／0

/// 拦截页视图。**不出现**：模式开关、退出/解锁/切换/跳过字样、时间点倒计时（"将于 X 点恢复"）。
/// 路径行：release ∅ → 结构上不生成；research ✓ → provider 提供，**取不到整句隐藏**。
struct InterceptCurtain: View {
    private let variant: BuildVariant
    private let state: AgeGateState
    private let pathProvider: SettingsPathProviding

    init(state: AgeGateState, variant: BuildVariant, pathProvider: SettingsPathProviding = BundledSettingsPathProvider()) {
        self.state = state
        self.variant = variant
        self.pathProvider = pathProvider
    }

    private var cell: AgeGateCell { AgeGateMatrix.cell(state: state, variant: variant) }
    private var curtains: [CurtainCopy] { AgeGateMatrix.curtainVariants(state: state, variant: variant) }

    var body: some View {
        // 无 curtain 键的态（adult / unverified）**结构上不生成拦截页**（不是隐藏）
        if !curtains.isEmpty {
            BottomSheetContainer {
                VStack(spacing: 16) {
                    ForEach(Array(curtains.enumerated()), id: \.offset) { _, curtain in
                        VStack(spacing: 6) {
                            Text(curtain.title)
                                .font(.headline)
                                .multilineTextAlignment(.center)
                            if !curtain.caption.isEmpty {
                                Text(curtain.caption)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }

                    // 系统路径行：由 (state, variant) 的 settingsPath 派生；
                    // 取不到（provider nil）→ **整句隐藏**（不硬编码、不自行翻译、不猜路径）
                    if let path = AgeGateMatrix.settingsPathText(state: state, variant: variant, provider: pathProvider) {
                        Text(path)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)   // 可复制（用户要在 App 与系统设置间往返）
                    }

                    Text("每日阅读时长上限：以家长侧设置为准")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding()
            }
            .background(Color(white: 0.98))
        }
    }
}

// MARK: - 年龄状态浮层（ageSheet，D-28 白名单 L3 容器）

/// 白名单容器 `ageSheet`：L3 ＋ 底部 sheet 高度口径（D-38）。
/// 本期演示三态状态条；**不设任何"完善/解除"按钮**——它是解释，不是出路
/// （出路只有系统设置，且以文字路径呈现）。
struct AgeSheet: View {
    let state: AgeGateState
    let variant: BuildVariant

    var body: some View {
        BottomSheetContainer {
            VStack(spacing: 12) {
                if let banner = AgeGateMatrix.bannerText(state: state, variant: variant) {
                    Text(banner).font(.headline)
                }
                Text("年龄信息由系统分龄提供；未完成确认前，部分能力按矩阵不可用。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .glassSurfaceL3()
    }
}

// MARK: - GlassSurface 便捷封装（白名单容器的 L3 用法）

extension View {
    /// L3 用法示例：ageSheet / 未来 setSheet / srcSheet 同型。
    /// **正文视图不得调用本扩展**（正文 0 玻璃的结构保证见 ReaderSurface.swift）。
    func glassSurfaceL3() -> some View {
        GlassSurface(strength: .l3, interactive: false) { self }
    }
}
