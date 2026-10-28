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

    /// 书架（FR-018 多副本发现用）；nil ＝ 未注入 → 面板只展示空候选（诚实空态）。
    let bookShelf: BookShelfStore?
    /// 当前年龄态（FR-032 ⑥）：`.minorConfirmed` 时进度写**模式内独立存储**，不污染主进度。
    let ageState: AgeGateState

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
    /// FR-014 四态收起：翻页/滚动中 → `.scrolling`（玻璃降为纯色+描边），静止 → `.steady`。
    @State private var glassPresentation: GlassPresentationState = .steady
    /// FR-011 书签：最近一次书签锚点（用于展示/测试断言）。
    @State private var lastBookmark: Bookmark?
    /// FR-018：是否呈现「换一个版本」面板。
    @State private var showVersionPicker = false
    /// FR-018：最近一次版本切换的对齐结果（诚实展示 exact/approximate/unavailable）。
    @State private var lastAlignment: VersionAlignment?
    /// FR-014：阅读设置浮层是否呈现（四条可用性由 ReaderSettingsSheet 承载）。
    @State private var showSettings = false
    /// UIT1 工具条显隐：**唯一入口 = 点按正文中央**（DESIGN §4.1），单手势、无自动恢复。
    @State private var toolbarVisible = true
    /// 浮层内可编辑的排版预设（与持久化预设同源）。
    @State private var editablePreset: ReaderTypography = TypographyPresetStore().load()
    /// EGG4 折角：是否处于折角跟手（长按已触发）。
    @State private var dogEarActive = false
    /// EGG4 折角：跟手的位移（pt）。
    @State private var dogEarTranslation: CGFloat = 0
    /// EGG4 折角：吸附后的静态折角（写书签成功时置为 true）。
    @State private var dogEarSnapped = false
    /// EGG4：长按判定延时任务（到 300ms 才真正进入折角；提前抬手则取消 → 判为短按翻页）。
    @State private var dogEarHoldTask: Task<Void, Never>?
    /// 目录是否呈现（`目录` 工具条入口）。
    @State private var showTOC = false
    /// 进度是否呈现（`进度` 工具条入口）。
    @State private var showProgress = false
    /// FR-018 版本对比：对比报告（nil ＝ 未打开）。
    @State private var compareReport: VersionDiff.Report?
    @State private var compareLeftName = ""
    @State private var compareRightName = ""

    public init(onExit: @escaping () -> Void, bookShelf: BookShelfStore? = nil,
                ageState: AgeGateState = .adultConfirmed) {
        self.onExit = onExit
        self.engine = nil
        self.bookShelf = bookShelf
        self.ageState = ageState
        _session = StateObject(wrappedValue: ReaderSession(engine: nil, coordinator: .shared))
    }

    public init(engine: ReaderEngine, onExit: @escaping () -> Void,
                bookShelf: BookShelfStore? = nil,
                ageState: AgeGateState = .adultConfirmed) {
        self.engine = engine
        self.onExit = onExit
        self.bookShelf = bookShelf
        self.ageState = ageState
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
                        // **EGG4 页角折角**（DESIGN §5 ④ 双判定）：右下 44×44 热区，
                        // <300ms 抬手 → 翻页；≥300ms → 折角跟手；松手 >12pt 吸附写书签。
                        // 关闭态由 MotionCoordinator 裁决（不注册时不进本分支），
                        // 此时加书签走工具条「书签」等价路径（功能不丢）。
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard DogEarGestureResolver.isInHotZone(
                                        value.startLocation,
                                        containerSize: ReaderLayout.shared.containerSize) else { return }
                                    if dogEarHoldTask == nil && !dogEarActive {
                                        // 按下：**先不判定**，起一个 300ms 延时；
                                        // 提前抬手 → 取消延时 → 按短按处理（翻页，该角不留死区）。
                                        dogEarHoldTask = Task { @MainActor in
                                            try? await Task.sleep(
                                                for: .seconds(DogEarGestureResolver.holdThresholdSeconds))
                                            guard !Task.isCancelled else { return }
                                            // 到时仍在按 → 进入折角跟手（一次 .light 宣告"进入折角"）
                                            dogEarActive = true
                                            glassPresentation = .gesture
                                            MotionCoordinator.shared.perform(.egg4DogEar) {}
                                        }
                                    }
                                    if dogEarActive {
                                        dogEarTranslation = value.translation.height
                                    }
                                }
                                .onEnded { _ in
                                    // 取消延时任务（无论是否已进入折角）
                                    dogEarHoldTask?.cancel()
                                    dogEarHoldTask = nil

                                    guard dogEarActive else {
                                        // **短按（<300ms 抬手）→ 翻页**：
                                        // 该角与"全屏右侧翻页"一致，不留死区。
                                        advancePageInDogEarZone()
                                        return
                                    }

                                    let outcome = DogEarGestureResolver.resolveRelease(
                                        verticalTranslation: dogEarTranslation)
                                    if outcome.writesBookmark {
                                        // **吸附 + 写书签必须走 MotionCoordinator**：
                                        // EGG4 的 triggerPolicy 是 `.dropTrigger`——关闭态下
                                        // 连触发一起短路（书签不写），这正是"彩蛋关掉后功能由
                                        // 工具条「书签」承担"的等价路径设计。
                                        MotionCoordinator.shared.perform(.egg4DogEar) {
                                            dogEarSnapped = true
                                            addBookmarkAtCurrentPage()
                                        }
                                    } else {
                                        dogEarSnapped = false   // 回弹，不写书签
                                    }
                                    dogEarActive = false
                                    dogEarTranslation = 0
                                    glassPresentation = .steady
                                }
                        )
                        // 手势期间玻璃降为纯色（`.gesture`），结束后 120ms 淡回。
                        .simultaneousGesture(
                            SpatialTapGesture().onEnded { value in
                                guard isCenterTap(value.location, size: ReaderLayout.shared.containerSize) else { return }
                                glassPresentation = .gesture
                                toolbarVisible.toggle()
                                Task { @MainActor in
                                    try? await Task.sleep(for: .seconds(GlassPresentationState.restoreDuration))
                                    glassPresentation = .steady
                                }
                            }
                        )
                        .onChange(of: session.currentPage) { _, _ in
                            recordProgressIfPossible()
                            // **FR-014 四态收起**：翻页/滚动中把工具条降为纯色+描边，
                            // 结束后 120ms（`GlassPresentationState.restoreDuration`）淡回完整玻璃。
                            // 只切 presentation（不插值材质参数），符合 DESIGN §2.5 通用规则。
                            glassPresentation = .scrolling
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(GlassPresentationState.restoreDuration))
                                glassPresentation = .steady
                            }
                        }
                }
                // **FR-014 阅读底部工具条**（玻璃白名单成员）：叠加在正文下方。
                // 翻页/滚动中 → `.scrolling` 降级纯色；静止 → `.steady` 完整玻璃。
                VStack {
                    Spacer()
                    if toolbarVisible {
                    ReaderToolbar(
                        presentation: glassPresentation,
                        onBookmark: addBookmarkAtCurrentPage,
                        onSwapVersion: { showVersionPicker = true },
                        onSettings: {
                            // FR-014：打开设置浮层前进入 `.transition`（380ms 材质冻结），
                            // 之后回到 `.steady`——**只调 opacity/transform，不插值材质参数**。
                            glassPresentation = .transition
                            showSettings = true
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(GlassPresentationState.transitionDuration))
                                glassPresentation = .steady
                            }
                        },
                        onTOC: { showTOC = true },
                        onProgress: { showProgress = true }
                    )
                    .transition(.identity)   // A 档：显隐直切，不用系统动画
                    }
                }
            } else {
                honestEmptyState
            }
        }
        // **`.onAppear` 位置修复（本次，台账待编号）**：旧写法把它挂在
        // `if let live = session.engine { ... }` 分支**内部**——`engine == nil` 时该分支不渲染，
        // 于是 `prepareSession()`（负责 `session.adopt(engine)`，把注入引擎装进会话）
        // 永不执行，空态成了死锁，注入的引擎永远进不来。移到外层 ZStack 即修复。
        .onAppear {
            prepareSession()
            // **FR-037：仅阅读器锁竖屏**（其他界面不受限）——进入即锁，退出即解。
            OrientationController.shared.lockReaderToPortrait()
        }
        // 目录（章节锚点跳转）
        .overlay {
            if showTOC, let live = session.engine {
                ReaderTOCSheet(
                    titles: tocTitles(for: live),
                    currentChapter: live.chapterID,
                    onSelect: { index in
                        jumpToChapter(index)
                        showTOC = false
                    },
                    onClose: { showTOC = false }
                )
                .transition(.opacity)
            }
        }
        // 进度（位置以 charOffset 表达）
        .overlay {
            if showProgress, let live = session.engine {
                ReaderProgressSheet(
                    chapterIndex: live.chapterID,
                    chapterCount: bookShelf?.item(for: live.bookID)?.chapters.count ?? 1,
                    pageIndex: session.currentPage,
                    pageCount: live.pageCount,
                    charOffset: live.page(at: session.currentPage)?.anchor.charOffset ?? 0,
                    onRestartChapter: {
                        if let first = live.page(at: 0)?.anchor.charOffset {
                            live.recordProgress(at: first)
                            session.currentPage = 0
                        }
                    },
                    onClose: { showProgress = false }
                )
                .transition(.opacity)
            }
        }
        // **FR-014 阅读设置浮层**（L3 玻璃白名单；四条可用性见 ReaderSettingsSheet）：
        // 自绘 overlay 而非系统 sheet —— 系统 sheet 的关闭方式不受我们控制，
        // 而 P0 要求 44pt 关闭按钮 / .escape / 36×4 把手 / scrim 点击关闭**四条都由我方实现**。
        .overlay {
            if showSettings {
                ReaderSettingsSheet(
                    preset: $editablePreset,
                    theme: $theme,
                    presentation: glassPresentation,
                    onClose: {
                        // 关闭前进入 `.transition`，避免浮层消失瞬间材质突变
                        glassPresentation = .transition
                        showSettings = false
                        // 落盘排版预设（档位归一化后写）
                        try? TypographyPresetStore().save(editablePreset)
                        try? ThemeStore().save(theme)
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(GlassPresentationState.transitionDuration))
                            glassPresentation = .steady
                            // 排版变更需重排（走既有链路，落点按 charOffset 重新二分）
                            session.applyTypography(TypographyTiers.normalize(editablePreset))
                        }
                    }
                )
                .transition(.opacity)
            }
        }
        // FR-018 版本对比（次入口）：逐章列出一致/有差异/仅一侧
        .overlay {
            if let report = compareReport {
                VersionCompareOverlay(report: report,
                                      leftName: compareLeftName,
                                      rightName: compareRightName,
                                      onClose: { compareReport = nil })
                    .transition(.opacity)
            }
        }
        // FR-018「换一个版本」面板：底部 sheet 类（D-38 高度口径由 BottomSheetContainer 承载）。
        .sheet(isPresented: $showVersionPicker) {
            if let live = session.engine {
                VersionPickerPanel(
                    current: currentCandidate(live),
                    candidates: versionCandidates(live),
                    onSelect: { candidate in
                        switchToVersion(candidate)
                        showVersionPicker = false
                    },
                    onCompare: { candidate in
                        // FR-018 次入口：**对指定候选**做逐章对比（指纹级，不做全文 diff）。
                        // 多副本时可逐个比对，不再是"只比最高匹配度那个"。
                        buildCompareReport(for: live, against: candidate)
                        showVersionPicker = false
                    },
                    onEditLabel: { id, label in
                        // FR-018：版本标签持久化（用户可编辑纯文本，空串回落默认值）
                        try? VersionLabelStore().setLabel(label, for: id)
                    }
                )
                .presentationDetents([.medium, .large])
            }
        }
        .onDisappear {
            recordProgressIfPossible()
            // **会话结束即释放内存页**（合规四禁令第 4 条）。
            // 此前只有签名变化才 invalidate，退出阅读器从不释放——禁令没有调用方。
            session.endSession()
            // **FR-037：退出阅读器解锁方向**（恢复其他界面可旋转）。
            OrientationController.shared.unlockAfterReader()
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
        let offset = page.anchor.charOffset

        // **FR-032 ⑥：模式内进度独立存储**——未成年人模式下只写模式内副本，
        // **不污染主进度**；经监护验证正常退出时由 `MinorModeExitCoordinator` 合并回去。
        if ageState == .minorConfirmed {
            let progress = ReadingProgress(bookID: live.bookID, chapterID: live.chapterID,
                                           charOffset: offset, fingerprint: page.anchor.fingerprint)
            try? MinorModeProgressStore().record(progress)
            return
        }
        live.recordProgress(at: offset)
    }

    /// UIT1 判定：点按是否落在**正文中央区域**（宽高各中间 1/3）。
    ///
    /// DESIGN §4.1：UIT1 唯一入口＝点按正文中央；**不得**加第二入口或自动恢复。
    private func isCenterTap(_ location: CGPoint, size: CGSize) -> Bool {
        guard size.width > 0, size.height > 0 else { return false }
        let thirdW = size.width / 3, thirdH = size.height / 3
        return location.x >= thirdW && location.x <= thirdW * 2
            && location.y >= thirdH && location.y <= thirdH * 2
    }

    /// 右下热区短按 → 翻页（EGG4 双判定的"翻页"一侧）。
    ///
    /// 与全屏右侧翻页一致：**该角不留死区**（DESIGN §5 ④ 原文）。
    /// 页边界收敛：末页不前进；首页不后退。
    private func advancePageInDogEarZone() {
        guard let live = session.engine else { return }
        let next = min(session.currentPage + 1, max(0, live.pageCount - 1))
        guard next != session.currentPage else { return }
        session.currentPage = next
    }

    // MARK: - 目录（按章节锚点跳转）

    /// 章节标题（来自 `ChapterAnchor.title`，不含正文——NFR-08）。
    private func tocTitles(for live: ReaderEngine) -> [String] {
        guard let item = bookShelf?.item(for: live.bookID) else { return [] }
        return item.chapters.map(\.title)
    }

    /// 跳到指定章：取该章正文 → 建新引擎 → 采纳并停在章首。
    ///
    /// 定位铁律：跳转后落点是**章首 `charOffset = 0`**，不是页码。
    private func jumpToChapter(_ index: Int) {
        guard let shelf = bookShelf,
              let live = session.engine,
              let item = shelf.item(for: live.bookID),
              index >= 0, index < item.chapters.count,
              let text = shelf.chapterText(for: item, chapterIndex: index) else { return }

        let newEngine = ReaderEngine(bookID: item.bookID, chapterID: index,
                                     chapterText: text, typography: live.typography,
                                     containerSize: ReaderLayout.shared.containerSize,
                                     progressStore: live.progressStore)
        newEngine.recordProgress(at: 0)
        session.adopt(newEngine)
        session.currentPage = 0
    }

    // MARK: - 多副本对齐（FR-018）

    /// 当前副本的面板候选（pin 行）。
    private func currentCandidate(_ live: ReaderEngine) -> VersionCandidate {
        let item = bookShelf?.item(for: live.bookID)
        let labelStore = VersionLabelStore()
        return VersionCandidate(
            id: live.bookID,
            fileName: item?.fileURL?.lastPathComponent ?? (item?.title ?? "当前章节"),
            versionLabel: labelStore.label(for: live.bookID) ?? VersionCandidate.defaultVersionLabel,
            fileSizeBytes: item?.fileURL
                .flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } ?? 0,
            format: (item?.fileURL?.pathExtension ?? "txt").uppercased(),
            matchScore: 1.0
        )
    }

    /// 其它本地副本（按匹配度降序）。无书架 → 空（诚实空态）。
    private func versionCandidates(_ live: ReaderEngine) -> [VersionCandidate] {
        guard let shelf = bookShelf,
              let current = shelf.item(for: live.bookID) else { return [] }
        return VersionDiscovery.candidates(
            current: current,
            shelf: shelf.items,
            headTail: { item in
                guard let head = shelf.chapterText(for: item, chapterIndex: 0) else { return nil }
                let last = max(0, item.chapters.count - 1)
                guard let tail = shelf.chapterText(for: item, chapterIndex: last) else { return nil }
                let win = VersionAlignmentEngine.fingerprintWindow
                let headPrefix = String((head as NSString).substring(to: min(win, (head as NSString).length)))
                let tailText = (tail as NSString)
                let tailSuffix = String(tailText.substring(from: max(0, tailText.length - win)))
                return (head: headPrefix, tail: tailSuffix)
            }
        )
    }

    /// 构建版本对比报告（FR-018 次入口）：逐章取两侧正文 → 指纹比较。
    ///
    /// **不做全文 diff**：长书全文 diff 会爆内存，且用户要的是"差在哪一章"，
    /// 不是逐字差异（那是编辑器的活）。
    private func buildCompareReport(for live: ReaderEngine, against candidate: VersionCandidate) {
        guard let shelf = bookShelf,
              let current = shelf.item(for: live.bookID),
              let target = shelf.item(for: candidate.id) else { return }

        let chapterCount = min(current.chapters.count, target.chapters.count)
        var leftTexts: [String] = []
        var rightTexts: [String] = []
        for index in 0..<chapterCount {
            leftTexts.append(shelf.chapterText(for: current, chapterIndex: index) ?? "")
            rightTexts.append(shelf.chapterText(for: target, chapterIndex: index) ?? "")
        }
        compareReport = VersionDiff.compare(left: leftTexts, right: rightTexts)
        compareLeftName = current.fileURL?.lastPathComponent ?? current.title
        compareRightName = candidate.fileName
    }

    /// **真实切换版本**：加载目标副本同章正文 → 用对齐引擎算出目标偏移 → 替换引擎并恢复位置。
    ///
    /// 定位铁律：切换后落点仍以 `charOffset` 表达，**不引入 pageIndex**。
    private func switchToVersion(_ candidate: VersionCandidate) {
        guard let shelf = bookShelf,
              let target = shelf.item(for: candidate.id),
              let live = session.engine else { return }

        let chapterIndex = min(live.chapterID, max(0, target.chapters.count - 1))
        guard let targetText = shelf.chapterText(for: target, chapterIndex: chapterIndex),
              !targetText.isEmpty else { return }

        // 对齐：源偏移 + 源章节首尾 → 目标章节，得 exact / approximate
        let ns = live.chapterText as NSString
        let win = VersionAlignmentEngine.fingerprintWindow
        let sourceHead = String(ns.substring(to: min(win, ns.length)))
        let sourceTail = String(ns.substring(from: max(0, ns.length - win)))
        let currentOffset = live.page(at: session.currentPage)?.anchor.charOffset ?? 0

        let alignment = VersionAlignmentEngine.align(
            sourceOffset: currentOffset,
            sourceChapterLength: max(1, ns.length),
            sourceHead: sourceHead, sourceTail: sourceTail,
            targetChapterText: targetText, targetChapterTitle: candidate.fileName
        )

        let newOffset: Int
        switch alignment {
        case .exact(let o), .approximate(let o, _): newOffset = o
        case .unavailable: newOffset = 0   // 无法对齐 → 从章首开始（诚实：不假装对齐）
        }

        // 建新引擎（沿用当前排版），写入对齐后的进度，再采纳进会话
        let typography = live.typography
        let newEngine = ReaderEngine(bookID: target.bookID, chapterID: chapterIndex,
                                     chapterText: targetText, typography: typography,
                                     containerSize: ReaderLayout.shared.containerSize,
                                     progressStore: live.progressStore)
        newEngine.recordProgress(at: newOffset)
        session.adopt(newEngine)
        session.restoreLanding()
        lastAlignment = alignment

        // **回写书架**（FR-018）：切换版本后，书架项的「继续阅读」锚点要指向新副本的目标位置，
        // 否则回到书架再点开仍是旧位置。`lastReadAnchor` 是 `ReadingProgress`（4 字段无 pageIndex）。
        let fingerprint = newEngine.page(at: newEngine.resolvePageIndex(for: newOffset))?
            .anchor.fingerprint ?? 0
        shelf.recordProgress(ReadingProgress(bookID: target.bookID,
                                             chapterID: chapterIndex,
                                             charOffset: newOffset,
                                             fingerprint: fingerprint))
    }

    // MARK: - 书签（FR-011）

    /// 在当前页页首加书签（**只存 `charOffset + fingerprint`**，无 pageIndex）。
    ///
    /// FR-011 与 EGG4 的联动：折角手势在关闭态不注册，**加书签走本工具条入口**（等价路径）。
    private func addBookmarkAtCurrentPage() {
        guard let live = session.engine,
              let page = live.page(at: session.currentPage) else { return }
        let anchor = page.anchor
        // 取页首若干字作预览（展示快照；定位仍以 offset/fingerprint 为准）
        let ns = live.chapterText as NSString
        let previewLen = min(30, max(0, ns.length - anchor.charOffset))
        let preview = previewLen > 0
            ? ns.substring(with: NSRange(location: anchor.charOffset, length: previewLen))
            : ""
        let bookmark = Bookmark(bookID: live.bookID, chapterID: live.chapterID,
                                charOffset: anchor.charOffset,
                                fingerprint: anchor.fingerprint,
                                preview: preview)
        let store = BookmarksStore()
        store.add(bookmark)
        try? store.persist()
        lastBookmark = bookmark
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
