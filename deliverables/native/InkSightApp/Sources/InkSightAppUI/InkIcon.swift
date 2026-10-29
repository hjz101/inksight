import SwiftUI
import InkSightAppKit

// MARK: - InkIcon（FR-028 第 ① 项：自绘图标，描边/端点随主题变）

/// 自绘图标（FR-028 第 ① 项：图标**色/描边/端点**随主题联动）。
///
/// **为什么必须自绘**：SF Symbols 是系统图元，**无法自定义描边宽度与端点形状**
/// （`strokeBorder` 对符号内部路径无效）。而 DESIGN §3.1 的判据明确要求
/// 「换主题后**图标端点形状必须肉眼可辨**」——用 SF Symbols 时这一项恒不变，
/// 属"某项不随主题动即判未完成"。故本组件用 `Path` 自绘。
///
/// token 化（DESIGN §3.1 原文）：`iconStroke` / `iconCap` **禁止硬编码**，
/// 全部取自 `ThemeSkinSpec.Spec`。
public struct InkIcon: View {

    /// 图标形状（覆盖项目实际用到的语义）。
    public enum Glyph {
        case close          // xmark
        case search         // magnifyingglass
        case back           // chevron.left
        case forward        // chevron.right
        case check          // checkmark
        case bookmark       // bookmark
        case list           // list.bullet
        case book           // book.pages
        case drop           // drop
        case swap           // arrow.left.arrow.right
        case note           // note.text
        case tag            // tag
        case waveform       // waveform（朗读）
        case gear           // 阅读设置
    }

    public let glyph: Glyph
    /// 主题规格（取 `iconColorHex`/`iconStroke`/`iconCap`）。
    public let spec: ThemeSkinSpec.Spec
    /// 尺寸（默认 20pt，常见 UI 图标尺寸）。
    public let size: CGFloat

    public init(_ glyph: Glyph, spec: ThemeSkinSpec.Spec, size: CGFloat = 20) {
        self.glyph = glyph
        self.spec = spec
        self.size = size
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let path = Self.path(for: glyph, in: canvasSize)
            let strokeStyle = StrokeStyle(
                lineWidth: CGFloat(spec.iconStroke),
                lineCap: spec.iconCap == .round ? .round : .butt,
                lineJoin: spec.iconCap == .round ? .round : .miter
            )
            context.stroke(path, with: .color(Color(hexString: spec.iconColorHex)),
                           style: strokeStyle)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// 图元路径（单位化：在 size×size 内绘制，边距 2pt 留描边空间）。
    ///
    /// **刻意用直线+圆弧组合**：端点形状（butt/round）在直线端点与折线拐角上
    /// **肉眼可辨**；若全用闭合曲线，butt 与 round 几乎无差别，判据就失效了。
    nonisolated static func path(for glyph: Glyph, in size: CGSize) -> Path {
        let w = size.width, h = size.height
        let m: CGFloat = 3          // 边距
        var p = Path()

        switch glyph {
        case .close:
            p.move(to: CGPoint(x: m, y: m))
            p.addLine(to: CGPoint(x: w - m, y: h - m))
            p.move(to: CGPoint(x: w - m, y: m))
            p.addLine(to: CGPoint(x: m, y: h - m))

        case .search:
            let r = (w - m * 2) * 0.32
            let c = CGPoint(x: m + r, y: m + r)
            p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            p.move(to: CGPoint(x: c.x + r * 0.7, y: c.y + r * 0.7))
            p.addLine(to: CGPoint(x: w - m, y: h - m))

        case .back:
            p.move(to: CGPoint(x: w - m, y: m))
            p.addLine(to: CGPoint(x: m, y: h / 2))
            p.addLine(to: CGPoint(x: w - m, y: h - m))

        case .forward:
            p.move(to: CGPoint(x: m, y: m))
            p.addLine(to: CGPoint(x: w - m, y: h / 2))
            p.addLine(to: CGPoint(x: m, y: h - m))

        case .check:
            p.move(to: CGPoint(x: m, y: h * 0.55))
            p.addLine(to: CGPoint(x: w * 0.42, y: h - m))
            p.addLine(to: CGPoint(x: w - m, y: m))

        case .bookmark:
            p.move(to: CGPoint(x: m, y: m))
            p.addLine(to: CGPoint(x: w - m, y: m))
            p.addLine(to: CGPoint(x: w - m, y: h - m))
            p.addLine(to: CGPoint(x: w / 2, y: h * 0.62))
            p.addLine(to: CGPoint(x: m, y: h - m))
            p.closeSubpath()

        case .list:
            let rowH = (h - m * 2) / 3
            for i in 0..<3 {
                let y = m + rowH * CGFloat(i) + rowH / 2
                p.move(to: CGPoint(x: m, y: y))
                p.addLine(to: CGPoint(x: w - m, y: y))
            }

        case .book:
            // 双页书：外框 + 中缝
            p.move(to: CGPoint(x: m, y: m))
            p.addLine(to: CGPoint(x: w / 2, y: m + 2))
            p.addLine(to: CGPoint(x: w - m, y: m))
            p.addLine(to: CGPoint(x: w - m, y: h - m))
            p.addLine(to: CGPoint(x: w / 2, y: h - m - 2))
            p.addLine(to: CGPoint(x: m, y: h - m))
            p.closeSubpath()
            p.move(to: CGPoint(x: w / 2, y: m + 2))
            p.addLine(to: CGPoint(x: w / 2, y: h - m - 2))

        case .drop:
            // 水滴：上尖下圆
            p.move(to: CGPoint(x: w / 2, y: m))
            p.addQuadCurve(to: CGPoint(x: w - m, y: h * 0.68),
                           control: CGPoint(x: w - m, y: h * 0.3))
            p.addQuadCurve(to: CGPoint(x: w / 2, y: h - m),
                           control: CGPoint(x: w / 2, y: h - m * 0.2))
            p.addQuadCurve(to: CGPoint(x: m, y: h * 0.68),
                           control: CGPoint(x: w / 2, y: h - m * 0.2))
            p.addQuadCurve(to: CGPoint(x: w / 2, y: m),
                           control: CGPoint(x: m, y: h * 0.3))

        case .swap:
            p.move(to: CGPoint(x: m, y: h * 0.35))
            p.addLine(to: CGPoint(x: w - m, y: h * 0.35))
            p.move(to: CGPoint(x: w - m, y: h * 0.65))
            p.addLine(to: CGPoint(x: m, y: h * 0.65))
            // 箭头（端点形状在箭尖可见）
            p.move(to: CGPoint(x: w - m * 2, y: h * 0.2))
            p.addLine(to: CGPoint(x: w - m, y: h * 0.35))
            p.addLine(to: CGPoint(x: w - m * 2, y: h * 0.5))
            p.move(to: CGPoint(x: m * 2, y: h * 0.5))
            p.addLine(to: CGPoint(x: m, y: h * 0.65))
            p.addLine(to: CGPoint(x: m * 2, y: h * 0.8))

        case .note:
            p.addRect(CGRect(x: m, y: m, width: w - m * 2, height: h - m * 2))
            for i in 0..<3 {
                let y = m + (h - m * 2) * (0.3 + CGFloat(i) * 0.22)
                p.move(to: CGPoint(x: m * 2, y: y))
                p.addLine(to: CGPoint(x: w - m * 2, y: y))
            }

        case .tag:
            p.move(to: CGPoint(x: m, y: m))
            p.addLine(to: CGPoint(x: w * 0.58, y: m))
            p.addLine(to: CGPoint(x: w - m, y: h * 0.42))
            p.addLine(to: CGPoint(x: w * 0.42, y: h - m))
            p.addLine(to: CGPoint(x: m, y: h * 0.58))
            p.closeSubpath()

        case .waveform:
            let midY = h / 2
            let bars: [CGFloat] = [0.3, 0.6, 1.0, 0.6, 0.3]
            let step = (w - m * 2) / CGFloat(bars.count - 1)
            for (i, scale) in bars.enumerated() {
                let x = m + step * CGFloat(i)
                let half = (h - m * 2) / 2 * scale
                p.move(to: CGPoint(x: x, y: midY - half))
                p.addLine(to: CGPoint(x: x, y: midY + half))
            }

        case .gear:
            // 齿轮：8 齿（端点形状在齿尖可辨）
            let c = CGPoint(x: w / 2, y: h / 2)
            let rOuter = (w - m * 2) / 2
            let rInner = rOuter * 0.62
            for i in 0..<8 {
                let angle = CGFloat(i) * .pi / 4
                let outer = CGPoint(x: c.x + cos(angle) * rOuter,
                                    y: c.y + sin(angle) * rOuter)
                let inner = CGPoint(x: c.x + cos(angle) * rInner,
                                    y: c.y + sin(angle) * rInner)
                p.move(to: inner)
                p.addLine(to: outer)
            }
            p.addEllipse(in: CGRect(x: c.x - rInner * 0.55, y: c.y - rInner * 0.55,
                                    width: rInner * 1.1, height: rInner * 1.1))
        }
        return p
    }
}
