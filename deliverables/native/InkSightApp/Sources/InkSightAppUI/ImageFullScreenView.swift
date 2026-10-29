import SwiftUI
import InkSightAppKit

// MARK: - ImageFullScreenView（FR-018-ac b：长图点击进全屏原图）

/// 全屏原图查看（FR-018-ac b：占位块点击进入）。
///
/// 纪律：
/// - **原图不裁**（占位块是 aspect-fill 裁过的，全屏要能看全——
///   这正是 PRD "长图点击进全屏原图" 的理由）；
/// - 支持捏合缩放与拖动（长图必须能看细节）；
/// - 四角关闭（44pt）＋ scrim 点击 ＋ `.escape`（与 FR-014 自绘浮层同型）。
struct ImageFullScreenView: View {
    let imageData: Data
    var onClose: () -> Void = {}

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.opacity(0.94).ignoresSafeArea()
                .onTapGesture { onClose() }

            if let image = platformImage(from: imageData) {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)   // **fit：原图不裁**
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { v in scale = min(max(lastScale * v, 1), 5) }
                                .onEnded { _ in lastScale = scale },
                            DragGesture()
                                .onChanged { v in
                                    offset = CGSize(width: lastOffset.width + v.translation.width,
                                                    height: lastOffset.height + v.translation.height)
                                }
                                .onEnded { _ in lastOffset = offset }
                        )
                    )
                    .accessibilityLabel("全屏图片")
            } else {
                Text("图片无法显示")
                    .foregroundStyle(.white)
            }

            // 关闭按钮（44pt，右上）
            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        // FR-028：图标须自绘（SF Symbols 无法自定义描边/端点）
                        ThemedInkIcon(.close, size: 17)
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.16), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭图片")
                    .accessibilityAction(.escape) { onClose() }
                    .padding(16)
                }
                Spacer()
            }
        }
        .accessibilityAction(.escape) { onClose() }
    }

    private func platformImage(from data: Data) -> Image? {
        #if canImport(UIKit)
        if let ui = UIImage(data: data) { return Image(uiImage: ui) }
        #endif
        if let provider = CGDataProvider(data: data as CFData),
           let cg = CGImage(pngDataProviderSource: provider, decode: nil,
                            shouldInterpolate: true, intent: .defaultIntent) {
            return Image(decorative: cg, scale: 1)
        }
        return nil
    }
}

#if canImport(UIKit)
import UIKit
#endif
