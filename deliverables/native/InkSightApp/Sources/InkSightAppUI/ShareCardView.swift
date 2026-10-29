import SwiftUI
import InkSightAppKit

// MARK: - ShareCardView（FR-023 分享卡）

/// 分享卡：**用配色生成**（FR-023 原文：不使用第三方书封图）。
///
/// 纪律：
/// - 卡面纯配色（主题强调色渐变），无书封图、无第三方素材；
/// - 行数据来自 `ReadingMetricsModel.shareLines()`（真实统计）；
/// - 可保存/分享（经系统 share sheet）。
struct ShareCardView: View {
    /// 分享文本行（真实统计）。
    let lines: [String]
    var onClose: () -> Void = {}

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // 卡面：配色渐变（FR-023：配色生成，非第三方书封图）
                VStack(spacing: 10) {
                    ThemedInkIcon(.drop, size: 15)
                        .foregroundStyle(.white)
                    Text("墨见 · 我的阅读")
                        .font(.headline)
                        .foregroundStyle(.white)
                    ForEach(lines, id: \.self) { line in
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.95))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(
                    LinearGradient(colors: [Color.blue.opacity(0.75),
                                            Color.purple.opacity(0.65)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18)
                )

                ShareLink(item: shareText) {
                    HStack(spacing: 6) { ThemedInkIcon(.upload, size: 15); Text("分享") }
                }
            }
            .padding()
            .navigationTitle("分享卡")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", action: onClose)
                }
            }
        }
    }

    /// 分享文本（纯文本，无图——保持诚实与最小实现）。
    private var shareText: String {
        "墨见 · 我的阅读\n" + lines.joined(separator: "\n")
    }
}
