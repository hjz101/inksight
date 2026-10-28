import SwiftUI
import InkSightAppKit
import InkSightCore

// MARK: - 备份导出/导入（FR-025）

/// 备份视图：导出/导入用户数据（进度＋排版偏好＋动效偏好）。
///
/// 纪律（FR-025）：
/// - 导出**只含**进度与偏好，**结构上无正文字段**（`BackupPayload` 类型保证）；
/// - 落盘格式带 `version`（P0 前置，老数据可迁移）；
/// - 导入未知更高版本拒绝（不读坏新格式）。
struct BackupView: View {
    @Environment(\.dismiss) private var dismiss

    let service: BackupService

    @State private var statusMessage = ""
    @State private var exportURL: URL?
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            Form {
                Section("导出") {
                    Text("导出内容：阅读进度、排版偏好、动效开关。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("**不含**任何书籍正文（结构上没有正文字段）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("生成备份文件") { performExport() }
                    if let url = exportURL {
                        LabeledContent("已生成", value: url.lastPathComponent)
                        Text(url.path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Section("导入") {
                    Text("导入会恢复进度与偏好；已有数据按书覆盖。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("选择备份文件导入") { showImporter = true }
                }

                if !statusMessage.isEmpty {
                    Section {
                        Text(statusMessage).font(.caption)
                    }
                }

                Section("格式版本") {
                    LabeledContent("当前备份格式版本",
                                   value: "v\(BackupPayload.currentVersion)")
                }
            }
            .navigationTitle("备份与恢复")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.json],
                          allowsMultipleSelection: false) { result in
                handleImport(result)
            }
        }
    }

    private func performExport() {
        do {
            let payload = try service.export()
            let data = try payload.encode()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("inksight-backup-v\(payload.version).json")
            // 落盘单门（E-04）：导出文件也经 Persist 门面写（临时导出目录不排除备份）
            try Persist.write(data, to: url, payload: .readingProgress,
                              excludedFromBackup: false).get()
            exportURL = url
            statusMessage = "已生成备份：\(payload.progress.count) 条进度。"
        } catch {
            statusMessage = "导出失败：\(error)"
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let payload = try BackupPayload.decode(data)
                try service.import(payload)
                statusMessage = "已导入：\(payload.progress.count) 条进度，格式 v\(payload.version)。"
            } catch BackupPayload.DecodeError.unsupportedVersion(let v) {
                statusMessage = "导入失败：备份格式版本 v\(v) 高于当前支持的 v\(BackupPayload.currentVersion)，请升级 App 后再导入。"
            } catch {
                statusMessage = "导入失败：\(error)"
            }
        case .failure(let error):
            statusMessage = "选择文件失败：\(error)"
        }
    }
}
