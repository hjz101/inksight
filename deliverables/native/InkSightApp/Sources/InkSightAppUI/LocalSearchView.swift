import SwiftUI
import InkSightAppKit

// MARK: - 本地全文检索（FR-024a）

/// 本地检索视图：检索**仅本地导入文件**（FR-024a）。
///
/// 纪律：
/// - 索引对象仅本地导入文件（在线书不索引，FR-024b）；
/// - 诚实空态：无索引内容时说「还没有可检索的内容」，**不伪装成"没搜到"**；
/// - 命中结果给出书/章定位（跳转能力由上层提供）。
struct LocalSearchView: View {
    @Environment(\.dismiss) private var dismiss

    /// 检索仓库（nil ＝ 未注入，走诚实空态）。
    let searchStore: LocalSearchStore?
    /// 命中项点击回调（携带当前查询词；上层可在原始章节中计算 UTF-16 偏移）。
    var onSelect: ((LocalSearchStore.SearchHit, String) -> Void)?

    @State private var query = ""
    @State private var hits: [LocalSearchStore.SearchHit] = []
    @State private var hasSearched = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 搜索框
                HStack {
                    ThemedInkIcon(.search, size: 15)
                        .foregroundStyle(.secondary)
                    TextField("搜索本地书中的句子", text: $query)
                        .onSubmit { performSearch() }
                    if !query.isEmpty {
                        Button {
                            query = ""
                            hits = []
                            hasSearched = false
                        } label: {
                            ThemedInkIcon(.close, size: 15)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                .padding()

                content
            }
            .navigationTitle("本地检索")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onChange(of: query) { _, _ in
                if query.isEmpty { hits = []; hasSearched = false }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let store = searchStore, store.indexedRowCount > 0 {
            if hasSearched && hits.isEmpty {
                honestEmptyState("没有找到匹配的内容", detail: "试试更短的词，或换一个关键词。")
            } else if hits.isEmpty {
                honestEmptyState("输入关键词开始检索", detail: "检索范围：本地导入的书，可离线。")
            } else {
                List(hits, id: \.self) { hit in
                    let row = VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(hit.bookTitle).font(.subheadline.weight(.medium))
                            Spacer()
                            Text("第 \(hit.chapterIndex + 1) 章")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        // snippet 是逐字空格 token 序列（FTS5 中文按字索引），展示前去掉多余空格
                        Text(Self.prettySnippet(hit.snippet))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 4)
                    if let onSelect {
                        Button { onSelect(hit, query); dismiss() } label: { row }
                            .buttonStyle(.plain)
                    } else {
                        row
                    }
                }
            }
        } else {
            // 诚实空态：还没索引过任何内容——不伪装成"没搜到"
            honestEmptyState("还没有可检索的内容",
                             detail: "导入本地书后会自动建立检索索引；检索只在本地进行，不联网。")
        }
    }

    private func honestEmptyState(_ title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            ThemedInkIcon(.search, size: 15)
                .foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private func performSearch() {
        guard let store = searchStore else { return }
        hits = store.search(query)
        hasSearched = true
    }

    /// 把 FTS5 的逐字空格片段还原成可读文本。
    ///
    /// 逐字索引产生的形如「定 位 铁 律」；判据是**空格两侧都是 CJK 才删**——
    /// 「用 Swift」之间是分隔符，必须保留（否则中文与英文粘连）。
    static func prettySnippet(_ raw: String) -> String {
        let chars = Array(raw)
        var result = ""
        for (i, ch) in chars.enumerated() {
            if ch == " " {
                let prev = i > 0 ? chars[i - 1] : nil
                let next = i + 1 < chars.count ? chars[i + 1] : nil
                // 两侧都是汉字 → 逐字索引产生的分隔，删除；否则是真实分隔符，保留
                if let p = prev, let n = next, p.isCJK, n.isCJK { continue }
            }
            result.append(ch)
        }
        return result
    }
}

private extension Character {
    var isCJK: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return (0x4E00...0x9FFF).contains(scalar.value)
            || (0x3400...0x4DBF).contains(scalar.value)
            || (0xF900...0xFAFF).contains(scalar.value)
    }
}
