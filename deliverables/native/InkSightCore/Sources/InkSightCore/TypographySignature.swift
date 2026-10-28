import Foundation
import CryptoKit

// MARK: - 排版参数（单一来源）

/// 四向内边距。
public struct ReaderInsets: Equatable, Sendable, Codable {
    public var top: Double
    public var leading: Double
    public var bottom: Double
    public var trailing: Double

    public init(top: Double, leading: Double, bottom: Double, trailing: Double) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }
}

/// 排版参数**单一来源**（技术约束清单 FR-031：`ReaderTypography` 唯一排版来源）。
///
/// 契约（原生阶段冻结项）：本结构的字段清单就是 `TypographySignature` 哈希输入的字段清单，
/// 两者必须同步演化；任何一个字段改名/增删都要走台账新编号。
public struct ReaderTypography: Equatable, Sendable, Codable {
    public var fontID: String
    public var fontSize: Double
    public var lineHeightMultiplier: Double
    public var paragraphSpacingBefore: Double
    public var paragraphSpacingAfter: Double
    public var insets: ReaderInsets
    public var indent: Double
    public var imagePlaceholderAspect: Double

    public init(fontID: String,
                fontSize: Double,
                lineHeightMultiplier: Double,
                paragraphSpacingBefore: Double,
                paragraphSpacingAfter: Double,
                insets: ReaderInsets,
                indent: Double,
                imagePlaceholderAspect: Double) {
        self.fontID = fontID
        self.fontSize = fontSize
        self.lineHeightMultiplier = lineHeightMultiplier
        self.paragraphSpacingBefore = paragraphSpacingBefore
        self.paragraphSpacingAfter = paragraphSpacingAfter
        self.insets = insets
        self.indent = indent
        self.imagePlaceholderAspect = imagePlaceholderAspect
    }

    /// 行盒 = 字号 × 倍数；渲染用 `minLineHeight == maxLineHeight == 本值`（行盒写死，
    /// 此时 CoreText 的 lineSpacing 不再生效，机制上杜绝「1.75 被实现成 1.75＋默认行距」）。
    public var lineHeight: Double { fontSize * lineHeightMultiplier }
}

// MARK: - TypographySignature

/// 排版签名：分页锚点与页位图缓存的 key。
///
/// 契约（原生阶段冻结项）：
/// 1. 哈希输入字段清单就是下面的 canonical 串，**字段顺序与命名不许静默改**（要改走台账新编号）。
/// 2. **禁则表版本号必须入签名**——禁则表一变断点就变，不入签名会让旧 PageAnchor
///    永久复用错页，且只能靠重装 App 才"修好"（技术约束清单原文）。
/// 3. `imagePlaceholderAspect` 是**排版参数**不是 UI 设置项：占位比例决定图片段高度 →
///    决定分页 → 决定缓存失效，不入签名会出现「改设置排版不变 / 页数对不上 / 翻到空白页」。
public struct TypographySignature: Equatable, Sendable, Codable {
    /// SHA-256 前 32 个十六进制字符（128bit，防碰撞足够且便于日志）。
    public let digest: String

    public init(typography: ReaderTypography,
                containerSize: CGSize,
                screenScale: Double,
                kinsokuVersion: Int) {
        var parts: [String] = []
        parts.append("v1")
        parts.append("fontID=\(typography.fontID)")
        parts.append("fontSize=\(typography.fontSize.fixed6)")
        parts.append("lineHeightMultiplier=\(typography.lineHeightMultiplier.fixed6)")
        parts.append("paragraphSpacingBefore=\(typography.paragraphSpacingBefore.fixed6)")
        parts.append("paragraphSpacingAfter=\(typography.paragraphSpacingAfter.fixed6)")
        parts.append("insets=\(typography.insets.top.fixed6),\(typography.insets.leading.fixed6),\(typography.insets.bottom.fixed6),\(typography.insets.trailing.fixed6)")
        parts.append("indent=\(typography.indent.fixed6)")
        parts.append("imagePlaceholderAspect=\(typography.imagePlaceholderAspect.fixed6)")
        parts.append("containerWidth=\(containerSize.width.fixed6)")
        parts.append("containerHeight=\(containerSize.height.fixed6)")
        parts.append("screenScale=\(screenScale.fixed6)")
        parts.append("kinsokuVersion=\(kinsokuVersion)")
        let canonical = parts.joined(separator: "|")
        let digest = SHA256.hash(data: Data(canonical.utf8))
        self.digest = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

extension Double {
    /// 与区域设置无关的定点格式（哈希输入禁止随 Locale 漂移）。
    ///
    /// **历史教训（E-02 同类）**：曾写成 `String(format: "%.6f", locale:)`——
    /// **漏传值参数**，所有数字恒为 "0.000000"，导致 fontSize/insets/containerSize
    /// 全部不参与哈希、测试全绿假象被「逐字段变化」测试当场抓出。
    /// 可变参数必须显式带上 `self`。
    var fixed6: String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), self)
    }
}

extension CGFloat {
    /// 同上（CGFloat 桥接 Double 后复用同一格式，保证 hash 输入无 Locale 漂移）。
    var fixed6: String {
        Double(self).fixed6
    }
}
