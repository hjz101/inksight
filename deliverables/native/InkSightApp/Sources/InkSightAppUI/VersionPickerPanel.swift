import SwiftUI
import InkSightAppKit

// MARK: - VersionPickerPanel（FR-018「换一个版本」面板）

/// 「换一个版本」面板（FR-018 ⑤）。
///
/// 纪律（逐条对齐 PRD）：
/// - **主按钮「换一个版本」**（短句、动词开头）；长句「替换为其他版本文件」保留给无障碍标签；
/// - 副标题 caption 13「选择另一份文件，保留进度与笔记」；
/// - **多副本按位置匹配度降序**；
/// - 字段：文件名／版本标签／**格式·大小**／位置匹配度，**不出现"源名"**；
/// - pin 行「当前：xxx.txt · 2.1MB · 未命名版本」；
/// - **版本标签用户可编辑，默认「未命名版本」，我方不预设任何值**；
/// - 页面文案**禁用**：全本／全本版／全集／完结版／补全／完整版／精校全本。
struct VersionPickerPanel: View {
    /// 当前版本（pin 行）。
    let current: VersionCandidate
    /// 其它本地副本（按匹配度降序展示）。
    let candidates: [VersionCandidate]
    /// 选择某副本（切换版本）。
    var onSelect: (VersionCandidate) -> Void = { _ in }
    /// 打开「版本对比」（次入口）：**针对指定候选**对比——多副本时可逐个比对，
    /// 而不是只比匹配度最高的那个。
    var onCompare: (VersionCandidate) -> Void = { _ in }
    /// 版本标签编辑后回调（FR-018：标签是可编辑纯文本，需持久化）。
    var onEditLabel: (String, String) -> Void = { _, _ in }

    /// 版本标签编辑态（用户可编辑纯文本）。
    @State private var editingLabelFor: String?
    @State private var draftLabel: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("换一个版本")
                .font(.title3.weight(.semibold))

            Text("选择另一份文件，保留进度与笔记")
                .font(.footnote)
                .foregroundStyle(.secondary)

            // pin 行：当前版本
            HStack(spacing: 6) {
                InkIcon(.pin, spec: ThemeSkinSpec.spec(for: .snowPaper), size: 15)
                Text("当前：\(current.fileName) · \(current.formatAndSize) · \(current.versionLabel)")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .accessibilityLabel("当前版本：\(current.fileName)，\(current.formatAndSize)，\(current.versionLabel)")

            Divider()

            // 候选列表（按匹配度降序）
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(VersionAlignmentEngine.ranked(candidates)) { candidate in
                        candidateRow(candidate)
                    }
                }
            }

            Divider()

            // 主按钮 ＋ 次入口
            Button {
                if let best = VersionAlignmentEngine.ranked(candidates).first {
                    onSelect(best)
                }
            } label: {
                Text("换一个版本").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            // 长句保留给无障碍标签（VoiceOver 读出来更准确）
            .accessibilityLabel("替换为其他版本文件")

            Button("版本对比") {
                if let best = VersionAlignmentEngine.ranked(candidates).first {
                    onCompare(best)
                }
            }
            .frame(maxWidth: .infinity)
            .disabled(candidates.isEmpty)
        }
        .padding(20)
    }

    @ViewBuilder
    private func candidateRow(_ candidate: VersionCandidate) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(candidate.fileName).font(.subheadline.weight(.medium))
                Spacer()
                Text(candidate.matchText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(candidate.matchScore >= 0.999 ? .green : .orange)
            }
            HStack(spacing: 8) {
                Text(candidate.formatAndSize)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("·")
                    .font(.caption2).foregroundStyle(.tertiary)
                // 版本标签：用户可编辑纯文本（点按进入编辑）
                Button {
                    editingLabelFor = candidate.id
                    draftLabel = candidate.versionLabel
                } label: {
                    Text(candidate.versionLabel)
                        .font(.caption2)
                        .underline()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("编辑版本标签：\(candidate.versionLabel)")
                Spacer()
                // 逐候选对比（FR-018 次入口的多副本形态）：不切换版本，只看差异
                Button("对比") { onCompare(candidate) }
                    .font(.caption2)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("与 \(candidate.fileName) 对比")
            }
            if editingLabelFor == candidate.id {
                HStack {
                    TextField(VersionCandidate.defaultVersionLabel, text: $draftLabel)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    Button("保存") {
                        if let id = editingLabelFor {
                            onEditLabel(id, draftLabel)
                        }
                        editingLabelFor = nil
                    }
                    .font(.caption)
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .onTapGesture { onSelect(candidate) }
    }
}
