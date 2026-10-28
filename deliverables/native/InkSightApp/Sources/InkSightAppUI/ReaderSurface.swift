import SwiftUI
import CoreText
import CoreGraphics
import InkSightAppKit
import InkSightCore

// MARK: - 阅读器表面（正文区 0 玻璃的结构保证）

/// 阅读正文容器（开发包 #4：真实排版渲染 ＋ 进度恢复 ＋ 五式翻页）。
///
/// **正文区 0 玻璃的结构保证**（回报第 ④ 项，类型层强制）：
/// 1. 全 App 的玻璃**只有一个入口**：`GlassSurface`（D-28 白名单 5 类容器专用）；
/// 2. 本类型**不引用 `GlassSurface`、不引用 `GlassStrength`、不调用 `.glassEffect`**，
///    公开 API 与 body 均不含任何玻璃修饰——玻璃在类型层面进不来；
/// 3. 正文背景一律不透明纯色/纸面 `Color(white: 0.98)`（温升 ≤4℃ 的前提：玻璃实时
///    backdrop 重算与 NFR-06 不可兼得）；
/// 4. 正文渲染只走 InkSightCore 的 `TypesetLine` 输出，**逐行自绘**（`CTLineDraw`），
///    不用 SwiftUI `Text` 重排（FR-031 零位移）。
///
/// 公开 API 维持 `onExit` 单一退出回调（骨架期契约不变）；新增 `engine` 注入实现真实渲染。
/// `engine == nil` 时退化为诚实空态（不伪装有书）。
public struct ReaderSurfaceView: View {

    public let onExit: () -> Void
    /// 阅读引擎（nil ＝ 诚实空态）。
    ///
    /// **注入的初始引擎**；开发包 #8 起，运行期换排版后以 `session.engine` 为当前生效引擎
    /// ——换排版得到的新引擎**不会被外部旧引擎覆盖**（见 `ReaderSession.adopt` 的同源判定）。
    let engine: ReaderEngine?

    /// 运行期会话（开发包 #8）：持有当前生效引擎与当前页，承载换排版与落点重定位。
    ///
    /// **`@State` → `@StateObject` 修复（本次，台账待编号）**：`ReaderSession` 是
    /// `ObservableObject`（`@Published engine/currentPage`），而 `@State` **只持有引用、
    /// 不订阅变更**——换排版替换 `session.engine` 后视图不会失效，用户看不到重排结果。
    /// `@StateObject` 才建立订阅。
    @StateObject private var session: ReaderSession

    @State private var config: ReaderConfig = .default
    /// 阅读主题（FR-010）：进入阅读器时按已存主题状态 + 当前小时解析生效皮肤。
    @State private var theme: ThemeState = ThemeStore().load()

    public init(onExit: @escaping () -> Void) {
        self.onExit = onExit
        self.engine = nil
        _session = StateObject(wrappedValue: ReaderSession(engine: nil, coordinator: .shared))
    }

    public init(engine: ReaderEngine, onExit: @escaping () -> Void) {
        self.engine = engine
        self.onExit = onExit
        // 用 App 级单例协调器（与设置页共用同一套锚点缓存——见 `PaginationCoordinator.shared`）
        _session = StateObject(wrappedValue: ReaderSession(engine: engine, coordinator: .shared))
    }

    /// **换排版公开入口**（开发包 #8）：同步重排当前章 → 落点按**同一 `charOffset`**
    /// 经新锚点重新二分定位 → 页面刷新。
    ///
    /// 定位铁律：落点靠 `charOffset` 重新二分，**不引入任何 `pageIndex` 依赖**。
    /// 无正文时返回 `.noContent`（诚实空态，不伪装成功）。
    @discardableResult
    public func applyTypography(_ typography: ReaderTypography,
                                containerSize: CGSize? = nil) -> RepaginationOutcome {
        session.applyTypography(typography, containerSize: containerSize)
    }

    public var body: some View {
        ZStack {
            // 纸面：不透明纯色（0 玻璃、0 backdrop 采样）——按生效主题取色（FR-010）
            ReaderPageCanvas.color(hex: theme.backgroundHex)
                .ignoresSafeArea()

            if let live = session.engine {
                VStack(spacing: 0) {
                    readerTopBar(live)
                    ReaderPager(engine: live, page: pageBinding, mode: config.pageTurnMode, theme: theme)
                        .onChange(of: session.currentPage) { _, _ in recordProgressIfPossible() }
                }
            } else {
                honestEmptyState
            }
        }
        // **`.onAppear` 位置修复（本次，台账待编号）**：旧写法把它挂在
        // `if let live = session.engine { ... }` 分支**内部**——`engine == nil` 时该分支不渲染，
        // 于是 `prepareSession()`（负责 `session.adopt(engine)`，把注入引擎装进会话）
        // 永不执行，空态成了死锁，注入的引擎永远进不来。移到外层 ZStack 即修复。
        .onAppear { prepareSession() }
        .onDisappear {
            recordProgressIfPossible()
            // **会话结束即释放内存页**（合规四禁令第 4 条）。
            // 此前只有签名变化才 invalidate，退出阅读器从不释放——禁令没有调用方。
            session.endSession()
        }
    }

    /// 当前页绑定（写入会话 → 触发进度回写）。
    private var pageBinding: Binding<Int> {
        Binding(
            get: { session.currentPage },
            set: { newValue in session.currentPage = newValue }
        )
    }

    /// 进入阅读器：采纳注入引擎 ＋ 按**持久化预设**排版。
    ///
    /// 若持久化预设与当前引擎排版不同 → **走重排链路**（不静默沿用旧排版）；
    /// 一致则直接恢复落点。
    private func prepareSession() {
        session.adopt(engine)
        let preset = TypographyPresetStore().load()
        if let live = session.engine, live.typography != preset {
            session.applyTypography(preset)
        } else {
            session.restoreLanding()
        }
    }

    // MARK: - 进度回写（只 charOffset＋fingerprint）

    /// 页/滚动停止时回写：取当前页首 charOffset，只存 charOffset＋fingerprint（FR-011 / 定位铁律）。
    ///
    /// **数据丢失修复（本次，台账待编号）**：旧写法是
    /// `live.page(at: session.currentPage)?.anchor.charOffset ?? 0` ——页索引一旦陈旧/越界
    /// （换排版后 `currentPage` 尚未对齐、快速翻页边界等），`page(at:)` 返回 nil，
    /// 于是 **offset 0 被当成"有效进度"落盘**，下次打开直接跳回章首，用户丢失阅读位置。
    ///
    /// 「取不到就别写」是唯一安全策略：**不上报**比**上报错误位置**要好——
    /// 漏一次回写最多丢一页的精度，写错一次则丢掉整本书的阅读位置。
    private func recordProgressIfPossible() {
        guard let live = session.engine else { return }
        guard let page = live.page(at: session.currentPage) else { return }   // 索引越界 → 不写，绝不写 0
        live.recordProgress(at: page.anchor.charOffset)
    }

    // MARK: - 顶栏（0 玻璃）

    /// 顶栏恒可达退出（能力矩阵：仿真/双页下边缘侧滑禁用，退出主路径＝顶栏）。
    /// 纯纸面背景，无任何玻璃修饰。
    private func readerTopBar(_ engine: ReaderEngine) -> some View {
        HStack(spacing: 12) {
            Button(action: onExit) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
            }
            .accessibilityLabel("退出阅读器")
            Spacer()
            Text("阅读器 · 第 \(engine.chapterID) 章")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 6)
        // 纸面底色透出，不叠加玻璃
    }

    // MARK: - 诚实空态（不伪装有书）

    private var honestEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.pages")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("阅读器 · 本期骨架页")
                .font(.headline)
            Text("未注入章节：正文渲染接入与翻页交互的确定性验证由注入示例章节的阅读器承载。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

// MARK: - 翻页容器（FR-008 五式；POC-5 转场动画标注）

/// 翻页容器：按 `PageTurnMode` 选择分页承载（横向/纵向滚动；翻页/卷曲的**真实转场动画**
/// 待真机 POC-5 校准，本期用同构的滚动分页承载，保证 macOS 测试构建与 iOS 一致可编译）。
/// 所有模式复用同一 `ReaderPageCanvas`（逐行自绘），保证渲染侧零位移逻辑一致。
struct ReaderPager: View {
    let engine: ReaderEngine
    @Binding var page: Int
    var mode: PageTurnMode
    /// 阅读主题（FR-010）。
    var theme: ThemeState = ThemeState()

    var body: some View {
        switch mode {
        case .none:
            ReaderPageCanvas(engine: engine, pageIndex: page, theme: theme)
        case .scroll, .flip, .curl:
            pagingScroll(.horizontal)
        case .vertical:
            pagingScroll(.vertical)
        }
    }

    /// 滚动分页容器（跨平台：macOS / iOS 同构）。每页占满视口，`.scrollTargetBehavior(.paging)`
    /// 实现整页吸附；`flip`/`curl` 的真实转场动画由 POC-5 接管，此处仅提供分页骨架。
    /// `page` 与滚动位置双向绑定：`scrollPosition(id:)` 既驱动恢复落点（进入即滚到恢复页），
    /// 也回写当前页（供进度回写 onChange 判定）。
    @ViewBuilder
    private func pagingScroll(_ axis: Axis.Set) -> some View {
        GeometryReader { geo in
            // **NFR-13 缺口 a 闭合（本次，台账 D-59 已登记）**：阅读器在此实测真实尺寸，
            // 回报给 `ReaderLayout.shared`（容器尺寸**单一来源**）——设置页与阅读器
            // 从此读同一尺寸 ⇒ `TypographySignature` 一致 ⇒ 两端缓存真正互通。
            // 只在尺寸变化时回报（布局回调可能频繁触发，去重避免无谓写入）。
            let size = geo.size
            Color.clear
                .frame(width: size.width, height: size.height)
                .onAppear {
                    ReaderLayout.shared.update(containerSize: size, screenScale: 1.0)
                }
                .onChange(of: size) { _, newSize in
                    ReaderLayout.shared.update(containerSize: newSize, screenScale: 1.0)
                }
            let pageID = Binding<Int?>(
                get: { page },
                set: { if let v = $0 { page = v } }
            )
            ScrollView(axis, showsIndicators: false) {
                if axis == .horizontal {
                    LazyHStack(spacing: 0) {
                        ForEach(0..<engine.pageCount, id: \.self) { idx in
                            ReaderPageCanvas(engine: engine, pageIndex: idx, theme: theme)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .id(idx)
                        }
                    }
                    .scrollTargetLayout()
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<engine.pageCount, id: \.self) { idx in
                            ReaderPageCanvas(engine: engine, pageIndex: idx, theme: theme)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .id(idx)
                        }
                    }
                    .scrollTargetLayout()
                }
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: pageID)
        }
    }
}

// MARK: - 单页画布（CoreText 逐行自绘；FR-031 零位移的渲染实现）

/// 单页正文画布：消费 `ReaderEngine` 的 `TypesetPage`，逐行 `CTLineDraw` 自绘。
///
/// 渲染纪律：
/// - 行来自 InkSightCore 的 `TypesetLine`（`charOffset`/`charLength`/`predictedWidth`），
///   由 `CoreTextLineCompositor` 重建等价 `CTLine`，**绝不 SwiftUI `Text` 重排**；
/// - 逐行经 `GraphicsContext.withCGContext` 取得 `CGContext`，按 `yTop ＋ ascent` 基线
///   `CTLineDraw`（x = 左内边距）；
/// - 背景纸面 `Color(white: 0.98)`，0 玻璃、0 backdrop。
///
/// 跨平台：`Canvas` + `withCGContext` 在 macOS 测试构建与 iOS 同构，无需 `UIViewRepresentable`。
struct ReaderPageCanvas: View {
    let engine: ReaderEngine
    let pageIndex: Int
    /// 阅读主题（FR-010）：决定纸面底色与正文墨色。
    var theme: ThemeState = ThemeState()
    /// 生效的皮肤（由 ReaderSurfaceView 按小时解析后传入；nil 时用 theme.skin）。
    var effectiveSkin: ThemeSkin?

    var body: some View {
        Canvas { context, _ in
            guard let page = engine.page(at: pageIndex) else { return }
            let comp = CoreTextLineCompositor(text: engine.chapterText, typography: engine.typography)
            let ys = comp.yTopPositions(for: page)

            context.withCGContext { cg in
                cg.saveGState()
                // 墨色按主题取（FR-010）：雪纸深色字 / 夜航两档对比
                let ink = Self.cgColor(hex: theme.textHex)
                cg.setFillColor(ink)
                cg.setStrokeColor(ink)

                for (i, line) in page.lines.enumerated() {
                    let ctLine = comp.line(for: line)
                    var ascent: CGFloat = 0, descent: CGFloat = 0, lead: CGFloat = 0
                    CTLineGetTypographicBounds(ctLine, &ascent, &descent, &lead)
                    let baseline = ys[i] + ascent
                    cg.textPosition = CGPoint(x: comp.leading, y: baseline)
                    CTLineDraw(ctLine, cg)
                }
                cg.restoreGState()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Self.color(hex: theme.backgroundHex))
    }

    /// 十六进制 → SwiftUI Color。
    static func color(hex: String) -> Color {
        Color(cgColor: cgColor(hex: hex))
    }

    /// 十六进制 → CGColor（`#RRGGBB`）。
    static func cgColor(hex: String) -> CGColor {
        var v = hex.trimmingCharacters(in: .whitespaces)
        if v.hasPrefix("#") { v.removeFirst() }
        guard v.count == 6, let n = UInt32(v, radix: 16) else {
            return CGColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1)
        }
        let r = CGFloat((n >> 16) & 0xFF) / 255
        let g = CGFloat((n >> 8) & 0xFF) / 255
        let b = CGFloat(n & 0xFF) / 255
        return CGColor(red: r, green: g, blue: b, alpha: 1)
    }
}
