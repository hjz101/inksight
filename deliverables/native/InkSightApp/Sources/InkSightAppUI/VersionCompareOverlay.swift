import SwiftUI
import InkSightAppKit

// MARK: - VersionCompareOverlay（FR-018 版本对比浮层）

/// 版本对比浮层（scrim ＋ L3 玻璃面板）。
///
/// **为什么单独成文件**：`ReaderSurface.swift` 受「正文区 0 玻璃」的结构保证约束
/// （`ReaderContractTests.testReaderSurfaceSourceHasNoGlassReference` 断言该文件
/// **不得出现 `GlassSurface`**）。浮层要用玻璃，就必须住在自己的文件里——
/// 这是纪律要求的拆分，不是风格偏好。
struct VersionCompareOverlay: View {
    let report: VersionDiff.Report
    let leftName: String
    let rightName: String
    var onClose: () -> Void = {}

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { onClose() }
                .accessibilityLabel("关闭版本对比")

            // 玻璃唯一入口（D-28 白名单：浮层与工具栏）
            GlassSurface(strength: .l3, interactive: true, cornerRadius: 22) {
                VersionCompareView(report: report,
                                   leftName: leftName,
                                   rightName: rightName,
                                   onClose: onClose)
                    .frame(maxHeight: 520)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .accessibilityAction(.escape) { onClose() }
        }
    }
}
