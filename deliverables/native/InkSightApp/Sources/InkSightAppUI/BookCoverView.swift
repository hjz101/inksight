import SwiftUI
import InkSightAppKit
import InkSightCore

// MARK: - BookCoverView（FR-007 书架封面）

/// 书架封面（FR-007：epub 解析出的封面；无封面时**用配色占位，不用第三方书封**）。
///
/// 纪律：
/// - 有 `coverImageData` → 真实封面（aspect-fill，**不裁坏**）；
/// - 无封面 → **配色占位**（书名首字 ＋ 渐变），与 FR-023 分享卡「不使用第三方书封图」同源；
/// - 占位配色由书名哈希决定 —— 同一本书的占位色**稳定**（不是每次随机，那样会闪）。
public struct BookCoverView: View {
    public let title: String
    public let coverData: Data?
    /// 封面尺寸。
    public let size: CGSize

    public init(title: String, coverData: Data?, size: CGSize = CGSize(width: 40, height: 56)) {
        self.title = title
        self.coverData = coverData
        self.size = size
    }

    public var body: some View {
        Group {
            if let data = coverData, let image = platformImage(from: data) {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .accessibilityHidden(true)   // 书名已有 Text，封面不重复朗读
    }

    /// 无封面：书名首字 ＋ 稳定渐变（色相由书名哈希决定）。
    private var placeholder: some View {
        let hue = Self.stableHue(for: title)
        return ZStack {
            LinearGradient(
                colors: [Color(hue: hue, saturation: 0.32, brightness: 0.82),
                         Color(hue: hue, saturation: 0.42, brightness: 0.62)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Text(String(title.prefix(1)))
                .font(.system(size: size.height * 0.34, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
    }

    /// 书名 → 稳定色相（0…1）。
    ///
    /// 用 FNV-1a（与项目其他指纹同源），**同书名恒定**——
    /// 若用 `random()`，每次重建视图颜色都会变，观感上像"封面在闪"。
    public static func stableHue(for title: String, salt: UInt64 = 0) -> Double {
        let hash = Fingerprint.fnv1a64(title) ^ salt
        return Double(hash % 360) / 360
    }

    /// 字节 → 平台图片（iOS 用 UIImage；跨平台用 CGImage 兜底）。
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
