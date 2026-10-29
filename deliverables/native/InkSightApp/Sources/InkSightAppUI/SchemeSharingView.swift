import SwiftUI
import InkSightAppKit
import InkSightCore

// MARK: - SchemeSharingView（FR-028 方案分享）

/// 阅读方案分享界面（FR-028：玻璃参数＋字体＋动效存为方案并分享）。
///
/// 纪律：
/// - **分享形态可读**（JSON 文本，用户能看清拷给别人的是什么）；
/// - **导入失败明确报错**，不静默回落（静默回落会让用户以为成功）；
/// - 方案**不含正文**（导出的只有偏好）。
struct SchemeSharingView: View {
    let typography: ReaderTypography
    let motion: MotionSettings
    let skin: ThemeSkinSpec.Skin
    var onClose: () -> Void = {}

    @State private var schemes: [ReaderScheme] = []
    @State private var draftName = ""
    @State private var importText = ""
    @State private var message = ""
    @State private var sharedText: String?
    @State private var store = ReaderSchemeStore()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("方案名称（可留空 → 未命名方案）", text: $draftName)
                    Button("保存当前设置为方案") {
                        let scheme = ReaderScheme(name: draftName, skin: skin,
                                                  typography: typography, motion: motion)
                        do {
                            try store.save(scheme)
                            message = "已保存：\(scheme.displayName)"
                            draftName = ""
                            reload()
                        } catch {
                            message = "保存失败：\(error.localizedDescription)"
                        }
                    }
                } header: {
                    Text("保存为方案")
                } footer: {
                    Text("方案包含主题皮肤、字体排版、动效开关；不含任何书籍内容或凭据。")
                }

                if !schemes.isEmpty {
                    Section("我的方案") {
                        ForEach(schemes, id: \.displayName) { scheme in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(scheme.displayName).font(.subheadline)
                                    Text("\(scheme.skin.displayName) · \(Int(scheme.typography.fontSize))pt")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("分享") {
                                    sharedText = try? ReaderSchemeCodec.encode(scheme)
                                }
                                .font(.caption)
                            }
                        }
                        .onDelete { indexSet in
                            for i in indexSet {
                                try? store.remove(named: schemes[i].displayName)
                            }
                            reload()
                        }
                    }
                }

                Section {
                    TextField("粘贴方案 JSON", text: $importText, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.caption.monospaced())
                    Button("导入方案") {
                        do {
                            let scheme = try ReaderSchemeCodec.decode(importText)
                            try store.save(scheme)
                            message = "已导入：\(scheme.displayName)"
                            importText = ""
                            reload()
                        } catch {
                            // **明确报错**：不静默回落
                            message = (error as? ReaderSchemeError)?.errorDescription
                                ?? error.localizedDescription
                        }
                    }
                    .disabled(importText.isEmpty)
                } header: {
                    Text("导入方案")
                } footer: {
                    Text("导入失败会说明原因（格式错误／版本不支持），不会静默忽略。")
                }

                if !message.isEmpty {
                    Section { Text(message).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("阅读方案")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: onClose)
                }
            }
            .onAppear(perform: reload)
            .sheet(item: Binding(
                get: { sharedText.map { SharedText(text: $0) } },
                set: { if $0 == nil { sharedText = nil } }
            )) { item in
                ShareLink(item: item.text) { Text("分享方案文本") }
                    .padding()
            }
        }
    }

    private func reload() {
        schemes = store.all()
    }
}

/// `sheet(item:)` 需要 Identifiable。
private struct SharedText: Identifiable {
    let text: String
    var id: String { text }
}
