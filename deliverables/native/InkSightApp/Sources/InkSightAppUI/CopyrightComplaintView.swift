import SwiftUI
import InkSightAppKit

// MARK: - 版权声明与投诉（FR-033 P0 合规基座；与原型 contactSheet 逐项对应）

/// 版权投诉表单视图。
///
/// 纪律（与原型 `contactSheet` 口径单一来源）：
/// - 投诉通达邮箱为 **`[TBD-CONTACT]` 占位**（发布闸门 A9/A10，发行前必须替换）；
/// - 明确展示受理回执 48h／处理 15 工作日／重复侵权 3 条下架的承诺；
/// - 需齐备四项材料，校验不过不提交；
/// - 表单用 `Form`（系统样式，不引入玻璃——投诉表单是信息承载，非玻璃白名单）。
struct CopyrightComplaintView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var rightsHolder = ""
    @State private var proofOfOwnership = ""
    @State private var infringingURL = ""
    @State private var goodFaithStatement = ""
    @State private var submitted = false
    @State private var errors: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("投诉通达") {
                    LabeledContent("邮箱", value: CopyrightComplaint.contactEmail)
                    Text("受理回执：收到投诉后 \(CopyrightComplaint.acknowledgmentHours) 小时内发出")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("处理结果：\(CopyrightComplaint.resolutionWorkdays) 个工作日内得出并答复")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("重复侵权：同一权利人同一站点重复侵权达 \(CopyrightComplaint.repeatInfringementThreshold) 条且指名同一具体章节，下架全部章节")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("需齐备材料（缺一不提交）") {
                    TextField("权利人主体信息", text: $rightsHolder)
                    TextField("权属证明", text: $proofOfOwnership)
                    TextField("侵权具体章节 URL", text: $infringingURL)
                    TextField("善意使用声明", text: $goodFaithStatement, axis: .vertical)
                        .lineLimit(3...6)
                }

                if !errors.isEmpty {
                    Section {
                        ForEach(errors, id: \.self) { error in
                            Text("⚠️ \(error)")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                if submitted {
                    Section {
                        Text("已记录投诉。受理回执将在 48 小时内发出；处置结果 15 个工作日内答复。")
                            .font(.caption)
                    }
                }

                Section {
                    Button(submitted ? "再次提交" : "提交投诉") {
                        let complaint = CopyrightComplaint(rightsHolder: rightsHolder,
                                                           proofOfOwnership: proofOfOwnership,
                                                           infringingURL: infringingURL,
                                                           goodFaithStatement: goodFaithStatement)
                        errors = complaint.validationErrors
                        if errors.isEmpty { submitted = true }
                    }
                    .disabled(submitted)
                }
            }
            .navigationTitle("版权声明与投诉")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
