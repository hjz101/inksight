import SwiftUI
import InkSightAppKit

// MARK: - VersionCompareView（FR-018 版本对比）

/// 版本对比视图（FR-018 次入口）：逐章列出「一致／有差异／仅一侧」。
///
/// 纪律：
/// - **不出现"源名"**（本地多副本，不是书源）；
/// - **禁词零命中**（全本／全集／完结版／补全／完整版／精校）；
/// - 无差异时**如实说「两个版本内容一致」**，不假装有差异、也不引导用户盲换。
struct VersionCompareView: View {
    /// 对比报告。
    let report: VersionDiff.Report
    /// 左侧（当前版本）名称。
    let leftName: String
    /// 右侧（候选版本）名称。
    let rightName: String
    /// 关闭回调。
    var onClose: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            // 头部（44pt 关闭按钮 ＋ 把手，与 FR-014 四条可用性同型）
            Capsule()
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .accessibilityHidden(true)

            HStack {
                Text("版本对比").font(.headline)
                Spacer()
                Button(action: onClose) {
                    InkIcon(.close, spec: ThemeSkinSpec.spec(for: .snowPaper), size: 15)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭版本对比")
                .accessibilityAction(.escape) { onClose() }
            }
            .padding(.horizontal, 20)

            // 汇总行
            HStack(spacing: 6) {
                Text(leftName).font(.caption2.weight(.medium))
                InkIcon(.swap, spec: ThemeSkinSpec.spec(for: .snowPaper), size: 15)
                Text(rightName).font(.caption2.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.bottom, 4)

            Text(report.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            if !report.hasDifferences {
                // 诚实：无差异就明说
                Text("两个版本内容一致")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
                Spacer()
            } else {
                List(report.chapters, id: \.chapterIndex) { diff in
                    HStack {
                        Text("第 \(diff.chapterIndex + 1) 章")
                            .font(.subheadline)
                        Spacer()
                        Text(diff.state.displayText)
                            .font(.caption)
                            .foregroundStyle(color(for: diff.state))
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func color(for state: VersionDiff.ChapterState) -> Color {
        switch state {
        case .identical: return .secondary
        case .different: return .orange
        case .leftOnly, .rightOnly: return .blue
        }
    }
}
