import SwiftUI
import InkSightAppKit

// MARK: - TTSPanel（FR-012 朗读面板）

/// 朗读面板：播放/暂停、0.5–2.5 倍速、定时关闭。
///
/// FR-014 四条可用性同型：44pt 关闭 / `.escape` / 36×4 把手 / scrim 点击关闭。
struct TTSPanel: View {
    @ObservedObject var engine: TTSEngine
    var onClose: () -> Void = {}

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { onClose() }
                .accessibilityLabel("关闭朗读")

            GlassSurface(strength: .l3, interactive: true, cornerRadius: 22) {
                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.45))
                        .frame(width: 36, height: 4)
                        .padding(.top, 10)
                        .accessibilityHidden(true)

                    HStack {
                        Text("朗读").font(.headline)
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("关闭朗读")
                        .accessibilityAction(.escape) { onClose() }
                    }
                    .padding(.horizontal, 20)

                    VStack(alignment: .leading, spacing: 16) {
                        // 播放/暂停
                        HStack(spacing: 16) {
                            Button {
                                switch engine.state {
                                case .idle: break
                                case .speaking: engine.pause()
                                case .paused: engine.resume()
                                }
                            } label: {
                                Image(systemName: engine.state == .speaking
                                      ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 44))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(engine.state == .speaking ? "暂停朗读" : "继续朗读")

                            VStack(alignment: .leading) {
                                Text(stateText).font(.subheadline)
                                Text("字符位置 \(engine.currentCharOffset)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        // 语速（0.5–2.5）
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("语速").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.1f×", engine.settings.clampedRate))
                                    .font(.caption)
                            }
                            Slider(value: Binding(
                                get: { engine.settings.clampedRate },
                                set: { engine.updateRate($0) }
                            ), in: TTSSettings.minRate...TTSSettings.maxRate, step: 0.1)
                        }

                        // 定时关闭
                        VStack(alignment: .leading, spacing: 6) {
                            Text("定时关闭").font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                sleepChip(nil, label: "关")
                                ForEach(TTSSettings.sleepTimerOptions, id: \.self) { m in
                                    sleepChip(m, label: "\(m) 分")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .accessibilityAction(.escape) { onClose() }
        }
    }

    private var stateText: String {
        switch engine.state {
        case .idle: return "未在朗读"
        case .speaking: return "正在朗读"
        case .paused: return "已暂停"
        }
    }

    private func sleepChip(_ minutes: Int?, label: String) -> some View {
        let active = engine.settings.sleepTimerMinutes == minutes
        return Button {
            engine.setSleepTimer(minutes: minutes)
        } label: {
            Text(label)
                .font(.system(size: 13, weight: active ? .semibold : .regular))
                .frame(minWidth: 48, minHeight: 36)
                .background(active ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05),
                            in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}
