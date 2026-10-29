import SwiftUI
import InkSightAppKit

// MARK: - ReaderTOCSheet（目录：按章节锚点跳转）

/// 阅读器目录（`目录` 工具条入口）。
///
/// 纪律：
/// - 列表来自 `ChapterAnchor`（只含 `(offset, byteLength)` 与标题，**不解析正文**，NFR-08）；
/// - 当前章高亮；点按跳转；
/// - 与 FR-014 同型的四条可用性（44pt 关闭 / `.escape` / 36×4 把手 / scrim 点击）。
struct ReaderTOCSheet: View {
    /// 章节标题列表（来自 `BookShelfItem.chapters`）。
    let titles: [String]
    /// 当前章索引（高亮）。
    let currentChapter: Int
    /// 选中某章（跳转）。
    var onSelect: (Int) -> Void = { _ in }
    /// FR-036「退 5 章」：上跳 5 章落章首（点击后回调，由阅读器实现跳转与提示）。
    var onBackFive: () -> Void = {}
    /// 关闭。
    var onClose: () -> Void = {}

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { onClose() }
                .accessibilityLabel("关闭目录")

            // **玻璃唯一入口**（D-28 白名单：浮层与工具栏）——不得直接 .regularMaterial
            GlassSurface(strength: .l3, interactive: true, cornerRadius: 22) {
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: 36, height: 4)
                    .padding(.top, 10)
                    .accessibilityHidden(true)

                HStack {
                    Text("目录").font(.headline)
                    // FR-036：**手势必须有可见入口**——「退 5 章」文字按钮（44pt 触控目标），
                    // 点击上跳 5 章落章首并提示「已退 5 章」。
                    // AC：全模块不得存在只能手势触达的功能（本按钮是唯一入口，非辅助）。
                    Button(action: onBackFive) {
                        Text("退 5 章")
                            .font(.system(size: 15, weight: .medium))
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("后退 5 章")
                    Spacer()
                    Button(action: onClose) {
                        InkIcon(.close, spec: ThemeSkinSpec.spec(for: .snowPaper), size: 17)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭目录")
                    .accessibilityAction(.escape) { onClose() }
                }
                .padding(.horizontal, 20)

                if titles.isEmpty {
                    // 诚实空态
                    Text("这本书没有可用的章节目录")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 28)
                } else {
                    List {
                        ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                            Button {
                                onSelect(index)
                            } label: {
                                HStack {
                                    Text(title)
                                        .font(.subheadline)
                                        .foregroundStyle(index == currentChapter ? .primary : .secondary)
                                    Spacer()
                                    if index == currentChapter {
                                        InkIcon(.bookmark, spec: ThemeSkinSpec.spec(for: .snowPaper), size: 15)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(index == currentChapter ? [.isSelected] : [])
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .frame(maxHeight: 520)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .accessibilityAction(.escape) { onClose() }
        }
    }
}

// MARK: - ReaderProgressSheet（进度：当前位置展示与定位）

/// 阅读器进度（`进度` 工具条入口）。
///
/// 纪律（FR-011）：
/// - 位置以 **`charOffset`** 表达（页码是派生值）；
/// - 展示「第 N/M 章 · 第 P/Q 页 · 字符偏移 X」；
/// - 可回到章首（保守且明确，不做"跳到百分比"这种易漂移的交互）。
struct ReaderProgressSheet: View {
    let chapterIndex: Int
    let chapterCount: Int
    let pageIndex: Int
    let pageCount: Int
    let charOffset: Int
    /// 回到本章开头。
    var onRestartChapter: () -> Void = {}
    var onClose: () -> Void = {}

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { onClose() }
                .accessibilityLabel("关闭进度")

            GlassSurface(strength: .l3, interactive: true, cornerRadius: 22) {
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: 36, height: 4)
                    .padding(.top, 10)
                    .accessibilityHidden(true)

                HStack {
                    Text("进度").font(.headline)
                    Spacer()
                    Button(action: onClose) {
                        InkIcon(.close, spec: ThemeSkinSpec.spec(for: .snowPaper), size: 15)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭进度")
                    .accessibilityAction(.escape) { onClose() }
                }
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("章节", value: "第 \(chapterIndex + 1) / \(chapterCount) 章")
                    LabeledContent("本页", value: "第 \(pageIndex + 1) / \(pageCount) 页")
                    // 定位铁律：进度以字符偏移为准，不用页码
                    LabeledContent("字符偏移", value: "\(charOffset)")
                    Button("回到本章开头", action: onRestartChapter)
                        .buttonStyle(.bordered)
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
}
