import SwiftUI
import InkSightAppKit

// MARK: - TagManagementView（FR-022 标签管理）

/// 标签管理界面（FR-022：标签重命名/删除/使用统计，一个标签跨书聚合）。
///
/// 纪律：
/// - 删除标签**只移除标签，划线本身保留**（删标签不能连内容一起删）；
/// - 重命名到已存在标签时**去重**（不产生两个同名标签）；
/// - 如实显示使用次数（不做"热门/推荐"之类引导）。
struct TagManagementView: View {
    let highlightsStore: HighlightsStore
    var onClose: () -> Void = {}

    @State private var tags: [(tag: String, count: Int)] = []
    @State private var renaming: String?
    @State private var draftName = ""
    @State private var message = ""

    var body: some View {
        NavigationStack {
            List {
                if tags.isEmpty {
                    // 诚实空态
                    Text("还没有标签")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tags, id: \.tag) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.tag).font(.subheadline)
                                Spacer()
                                Text("\(item.count) 处").font(.caption).foregroundStyle(.secondary)
                            }
                            if renaming == item.tag {
                                HStack {
                                    TextField("新标签名", text: $draftName)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.caption)
                                    Button("保存") {
                                        let n = highlightsStore.renameTag(item.tag, to: draftName)
                                        message = n > 0 ? "已重命名 \(n) 处" : "重命名失败（名称重复或为空）"
                                        renaming = nil
                                        reload()
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                let n = highlightsStore.deleteTag(item.tag)
                                message = "已从 \(n) 处划线移除该标签（划线保留）"
                                reload()
                            } label: {
                                Text("删除")
                            }
                            Button {
                                renaming = item.tag
                                draftName = item.tag
                            } label: {
                                Text("重命名")
                            }
                        }
                    }
                }
                if !message.isEmpty {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("标签管理")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: onClose)
                }
            }
            .onAppear(perform: reload)
        }
    }

    private func reload() {
        tags = highlightsStore.tagUsage()
    }
}
