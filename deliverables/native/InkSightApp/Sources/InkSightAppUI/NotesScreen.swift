import SwiftUI
import InkSightAppKit

// MARK: - 墨迹（FR-013 划线入口 ＋ FR-022 标签化笔记）

/// 墨迹 Tab：划线/笔记列表（FR-013 展示侧 ＋ FR-022 标签聚合）。
///
/// 纪律：
/// - 诚实空态：无划线时说「还没有划线」，不伪装有内容；
/// - 划线锚点定位铁律同源（`charOffset + fingerprint`，无 pageIndex）；
/// - 标签筛选：选标签后只显示该标签的划线（FR-022 一个标签跨书聚合）。
struct NotesScreen: View {
    /// 划线仓库（nil ＝ 未注入，诚实空态）。
    let highlightsStore: HighlightsStore?

    /// 全部标签（去重，供筛选）。
    private var allTags: [String] {
        guard let store = highlightsStore else { return [] }
        var seen = Set<String>()
        var tags: [String] = []
        for h in store.allHighlights() {
            for t in h.tags where !seen.contains(t) {
                seen.insert(t)
                tags.append(t)
            }
        }
        return tags
    }

    var body: some View {
        NavigationStack {
            Group {
                if let store = highlightsStore, !store.allHighlights().isEmpty {
                    List {
                        if !allTags.isEmpty {
                            // 标签筛选条（FR-022 跨书聚合）
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    tagChip("全部", active: selectedTag == nil) { selectedTag = nil }
                                    ForEach(allTags, id: \.self) { tag in
                                        tagChip(tag, active: selectedTag == tag) { selectedTag = tag }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        ForEach(visibleHighlights, id: \.self) { highlight in
                            highlightRow(highlight)
                        }
                    }
                } else {
                    // 诚实空态：不伪装有划线
                    VStack(spacing: 10) {
                        Spacer()
                        ThemedInkIcon(.highlighter, size: 15)
                            .foregroundStyle(.tertiary)
                        Text("还没有划线")
                            .font(.headline)
                        Text("阅读时长按选中句子，即可划线、写想法、加标签。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        Spacer()
                    }
                }
            }
            .navigationTitle("墨迹")
        }
    }

    @State private var selectedTag: String?

    private var visibleHighlights: [Highlight] {
        guard let store = highlightsStore else { return [] }
        if let tag = selectedTag { return store.highlights(tag: tag) }
        return store.allHighlights()
    }

    private func tagChip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(active ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(active ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05),
                            in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func highlightRow(_ highlight: Highlight) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // 选中文本（快照）
            Text(highlight.selectedText)
                .font(.body)
                .foregroundStyle(.primary)
                .padding(.vertical, 2)
                .padding(.horizontal, 8)
                .background(Color.accentColor.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 3))
            if !highlight.note.isEmpty {
                Text(highlight.note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text("第 \(highlight.chapterID + 1) 章")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                if !highlight.tags.isEmpty {
                    ForEach(highlight.tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}
