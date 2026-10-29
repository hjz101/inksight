import SwiftUI
import InkSightAppKit

// MARK: - DogEarView（EGG4 页角折角视觉）

/// 页角折角视觉（EGG4：`24→60pt / 保持 3s`）。
///
/// **规格（PRD EGG4 原文）**：
/// - 跟手阶段尺寸 **24pt → 60pt**（随拉动比例增长）；
/// - 吸附后**保持 3s** 再消失；
/// - 画在**右下角**（与 44×44pt 双判定热区同角）。
///
/// 画法：折角是"纸张被掀起一角"——用两条边＋一条斜边构成三角形，
/// 内侧再画一条略短的折痕线。颜色取主题墨色（不用强调色：折角是纸的属性，
/// 不是交互反馈；用强调色会让人以为可以点）。
struct DogEarView: View {

    /// 当前尺寸（24…60pt）。
    public let size: CGFloat
    /// 墨色（主题正文色）。
    public let inkHex: String
    /// 纸面色（折角背面比纸面略深一点，形成"翻起来"的立体感）。
    public let paperHex: String

    /// 跟手最小尺寸（PRD：24pt）。
    public static let minSize: CGFloat = 24
    /// 吸附尺寸（PRD：60pt）。
    public static let maxSize: CGFloat = 60
    /// 保持时长（PRD：3s）。
    public static let holdDuration: TimeInterval = 3

    public init(size: CGFloat, inkHex: String, paperHex: String) {
        self.size = size
        self.inkHex = inkHex
        self.paperHex = paperHex
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let s = min(size, min(canvasSize.width, canvasSize.height))
            let w = canvasSize.width
            let h = canvasSize.height
            // 折角三角形：右下角，斜边从左下到右上
            var triangle = Path()
            triangle.move(to: CGPoint(x: w - s, y: h))
            triangle.addLine(to: CGPoint(x: w, y: h - s))
            triangle.addLine(to: CGPoint(x: w, y: h))
            triangle.closeSubpath()

            // 折角背面（略深于纸面，形成翻起感）
            context.fill(triangle, with: .color(Color(hexString: paperHex).opacity(0.92)))

            // 折痕斜边（1pt 墨色线）
            var crease = Path()
            crease.move(to: CGPoint(x: w - s, y: h))
            crease.addLine(to: CGPoint(x: w, y: h - s))
            context.stroke(crease, with: .color(Color(hexString: inkHex).opacity(0.55)),
                           style: StrokeStyle(lineWidth: 1, lineCap: .round))

            // 内侧再一条更短的折痕（让"纸被折过"更可信）
            var inner = Path()
            let inset = s * 0.28
            inner.move(to: CGPoint(x: w - s + inset, y: h))
            inner.addLine(to: CGPoint(x: w, y: h - s + inset))
            context.stroke(inner, with: .color(Color(hexString: inkHex).opacity(0.22)),
                           style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)   // 折角不拦截触摸（热区由手势层处理）
        .accessibilityHidden(true)
    }

    /// 把拉动位移映射为折角尺寸（24→60pt，线性）。
    ///
    /// - Parameter translation: 纵向拉动位移（pt），12pt 为吸附阈值起算点。
    public static func size(forTranslation translation: CGFloat) -> CGFloat {
        // 从吸附阈值（12pt）起算到 96pt 拉满
        let start: CGFloat = 12
        let end: CGFloat = 96
        let t = min(max((translation - start) / (end - start), 0), 1)
        return minSize + (maxSize - minSize) * t
    }
}
