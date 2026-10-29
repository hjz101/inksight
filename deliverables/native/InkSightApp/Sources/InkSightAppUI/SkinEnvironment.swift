import SwiftUI
import InkSightAppKit

// MARK: - SkinEnvironment（FR-028 全站皮肤联动的注入通道）

/// 主题皮肤的环境注入（替代各处硬编码 `ThemeSkinSpec.spec(for: .snowPaper)`）。
///
/// **为什么需要 Environment**：D-97 做图标全量替换时，31 处都写死了雪纸规格——
/// 结果**只有阅读工具条跟随主题**，其余页面换皮肤时图标描边/端点/颜色纹丝不动。
/// 这正好撞上 DESIGN §3.1 的判据「任一项不随主题动即判未完成」。
///
/// 用 `EnvironmentValues` 下传而非逐级传参：调用点太多（11 个文件），
/// 逐级传参会污染大量视图签名，且容易漏传——**漏传就是又一个"不随主题动"**。
private struct ThemeSkinSpecKey: EnvironmentKey {
    static let defaultValue: ThemeSkinSpec.Spec = ThemeSkinSpec.spec(for: .snowPaper)
}

public extension EnvironmentValues {
    /// 当前主题皮肤规格（根视图注入，全站读取）。
    var themeSkinSpec: ThemeSkinSpec.Spec {
        get { self[ThemeSkinSpecKey.self] }
        set { self[ThemeSkinSpecKey.self] = newValue }
    }
}

public extension View {
    /// 注入主题皮肤（在根视图调用一次）。
    func themeSkin(_ spec: ThemeSkinSpec.Spec) -> some View {
        environment(\.themeSkinSpec, spec)
    }
}

// MARK: - InkIcon 便捷初始化（从 Environment 取规格）

/// 从环境读规格的图标（**推荐用法**）。
///
/// 用法：`InkIcon(.close, size: 17)` —— 规格自动来自 `\.themeSkinSpec`，
/// 不必在每个调用点写 `spec:`（那样仍会写死，只是把 `.snowPaper` 换成了变量名）。
public struct ThemedInkIcon: View {
    let glyph: InkIcon.Glyph
    let size: CGFloat
    @Environment(\.themeSkinSpec) private var spec

    public init(_ glyph: InkIcon.Glyph, size: CGFloat = 20) {
        self.glyph = glyph
        self.size = size
    }

    public var body: some View {
        InkIcon(glyph, spec: spec, size: size)
    }
}
