import SwiftUI
import InkSightAppKit
import InkSightCore
import UniformTypeIdentifiers

// MARK: - 诚实空态（骨架页纪律：不伪装有内容）

/// 空态必须诚实：**不得伪装成有内容**（强反模式「假装有书的空书架」）。
/// 占位文案写明「本期骨架页，内容后续开发」。
struct HonestPlaceholder: View {
    let screenName: String
    var body: some View {
        VStack(spacing: 12) {
            ThemedInkIcon(.tray, size: 15)
                .foregroundStyle(.tertiary)
            Text("\(screenName) · 本期骨架页")
                .font(.headline)
            Text("内容后续开发。本页不预置任何内容，不伪装有书。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 发现（onlineSources 矩阵 gate；release ∅ 结构上沉默）

/// 发现页：本地导入区常驻；在线书源区由 `(state, variant)` 的 `onlineSources` 派生。
/// release 下 `onlineSources == .absent` → 在线区**结构上不生成**（沉默，非隐藏）——AGE_MATRIX §0 三值语义。
struct DiscoveryScreen: View {
    let ageState: AgeGateState
    let variant: BuildVariant

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("发现").font(.title.bold())
                // 本地书库区（诚实：本期仅支持本地导入；导入走 ChapterScanner 字节流分章，正文不进内存）
                DiscoveryRegionCard(title: "本地书库",
                                   caption: "从文件 App 导入本地 txt；分章走 ChapterScanner 字节流扫描，正文不进内存。")
                // 在线书源区：仅当矩阵允许在线源时生成（release 下 .absent → 不生成此区）
                if AgeGateMatrix.cell(state: ageState, variant: variant).onlineSources != .absent {
                    OnlineSourcesRegion(state: ageState, variant: variant)
                }
            }
            .padding()
        }
    }
}

private struct DiscoveryRegionCard: View {
    let title: String
    let caption: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(caption).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// 在线书源区（仅研究版可见；发行版 ∅ 结构上不生成）。文案由矩阵 `onlineSources` 派生，不硬编码。
private struct OnlineSourcesRegion: View {
    let state: AgeGateState
    let variant: BuildVariant

    var body: some View {
        let cell = AgeGateMatrix.cell(state: state, variant: variant)
        let caption: String = switch cell.onlineSources {
        case .restricted: "研究版：在线书源存在，但未成年人模式下不可用。"
        case .granted:    "研究版：在线书源可用（发行版结构上不生成此区）。"
        case .absent:     "（不应出现：absent 时本区已结构性不生成）"
        }
        DiscoveryRegionCard(title: "在线书源", caption: caption)
    }
}

// MARK: - 墨量（成就卡 L2；minutesTBD 不解包）

/// 墨量页：成就卡（L2 玻璃，D-28 白名单：成就卡片）。
///
/// 每日阅读时长上限**不解包** `DailyReadingQuota.minutesTBD`（D-03：无依据不造数，且绝不 force-unwrap）；
/// 仅以「以家长侧设置为准」静态文案呈现。成就计数取书架真实导入数（不伪造）。
struct InkScreen: View {
    let bookShelf: BookShelfStore

    /// 本地检索仓库（FR-024a）；nil ＝ 未注入（诚实空态）。
    var searchStore: LocalSearchStore?
    @State private var showSearch = false
    /// FR-023 墨量统计引擎（单例，跨会话累计）。
    @StateObject private var metricsModel = ReadingMetricsModel.shared
    /// 分享卡是否呈现。
    @State private var showShareCard = false
    /// FR-023：阅读轨迹切换点（已合并）。
    @State private var trajectoryDots: [TrajectoryDot] = []
    /// FR-023：展开说明的点。
    @State private var expandedDotID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("墨量").font(.title.bold())

                // FR-024a 本地全文检索入口（检索面：墨量 Tab，PRD §2.0）
                Button {
                    showSearch = true
                } label: {
                    HStack {
                        ThemedInkIcon(.search, size: 15)
                        Text("在本地书里找一句话")
                        Spacer()
                        ThemedInkIcon(.forward, size: 15)
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                // FR-023 墨量统计：时长/本数/连续天/时段分布（真实数据，诚实空态不伪造）
                GlassSurface(strength: .l2, interactive: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("阅读成就").font(.headline)
                        let summary = metricsModel.summary

                        // 时长（无数据 → 诚实显示「尚未记录」，不伪造 0）
                        HStack {
                            Text("累计阅读").font(.subheadline)
                            Spacer()
                            if let total = summary.totalMinutes {
                                Text("\(Int(total)) 分钟").font(.subheadline.weight(.medium))
                            } else {
                                Text("尚未记录").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        HStack {
                            Text("读过").font(.subheadline)
                            Spacer()
                            Text("\(summary.bookCount) 本").font(.subheadline.weight(.medium))
                        }
                        HStack {
                            Text("连续阅读").font(.subheadline)
                            Spacer()
                            Text("\(summary.streakDays) 天").font(.subheadline.weight(.medium))
                        }
                        // 时段分布（仅显示有记录的时段）
                        if !summary.distribution.isEmpty {
                            Divider()
                            Text("时段分布").font(.caption).foregroundStyle(.secondary)
                            ForEach(ReadingMetrics.TimeSlot.allCases, id: \.rawValue) { slot in
                                if let minutes = summary.distribution[slot], minutes > 0 {
                                    HStack {
                                        Text(slot.displayName).font(.caption)
                                        Spacer()
                                        Text("\(Int(minutes)) 分钟").font(.caption)
                                    }
                                }
                            }
                        }
                        // 每日阅读时长上限：以家长侧设置为准。
                        Text("每日阅读时长上限：以家长侧设置为准")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        // **FR-023 阅读轨迹**：切换点用 6pt 中性圆点标在进度轴上
                        // （间距 <12pt 合并 + 「+N」；点击只出中性说明）
                        if !trajectoryDots.isEmpty {
                            Divider()
                            Text("阅读轨迹").font(.caption).foregroundStyle(.secondary)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    // 轨迹轴（细线，中性色）
                                    Capsule()
                                        .fill(Color.secondary.opacity(0.2))
                                        .frame(height: 1)
                                    ForEach(trajectoryDots) { dot in
                                        TrajectoryDotView(dot: dot,
                                                          isExpanded: expandedDotID == dot.id)
                                            .position(x: geo.size.width * dot.position,
                                                      y: geo.size.height / 2)
                                            .onTapGesture {
                                                expandedDotID = (expandedDotID == dot.id) ? nil : dot.id
                                            }
                                    }
                                }
                            }
                            .frame(height: 28)
                        }

                        // 分享卡（配色生成，非第三方书封）
                        Button {
                            showShareCard = true
                        } label: {
                            HStack(spacing: 6) { ThemedInkIcon(.upload, size: 15); Text("生成分享卡") }
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .onAppear {
                    metricsModel.bookShelf = bookShelf
                    metricsModel.refresh()
                    // FR-023：轨迹轴长度按基准视口估算（393 - 80 内边距 = 313pt）
                    // **不用 UIScreen**（iOS 专属，macOS 测试构建编译不过）；
                    // 313pt 是 DESIGN §2.6 基准视口口径，真实屏宽差异只影响像素间距，
                    // 而合并阈值判据本身就是"视觉上挤不挤"，用基准值足够。
                    let axisLength: CGFloat = 313
                    trajectoryDots = TrajectoryRenderer.dots(from: TrajectoryLog(),
                                                             axisLength: axisLength)
                }
                .sheet(isPresented: $showShareCard) {
                    ShareCardView(lines: metricsModel.shareLines())
                }
            }
            .padding()
        }
        .sheet(isPresented: $showSearch) {
            LocalSearchView(searchStore: searchStore) { hit, query in
                // FR-024a 检索跳转：跨 Tab 无法直接传视图状态，经 App 级路由器投递请求，
                // 由书架 Tab 的阅读器宿主消费（`ShelfScreen` 监听 onAppear/通知）。
                // FTS5 不直接提供原文 UTF-16 offset；从本地原始章节二次扫描，
                // 不把全文常驻索引，命中后把精确偏移交给阅读器恢复页。
                let offset: Int?
                if let item = bookShelf.item(for: hit.bookID),
                   let text = bookShelf.chapterText(for: item, chapterIndex: hit.chapterIndex) {
                    let range = (text as NSString).range(of: query)
                    offset = range.location == NSNotFound ? nil : range.location
                } else {
                    offset = nil
                }
                ReaderNavigator.shared.request(ReaderNavigationRequest(bookID: hit.bookID,
                                                                       chapterIndex: hit.chapterIndex,
                                                                       charOffset: offset))
            }
        }
    }
}

// MARK: - 书架（GlassSurface L2 继续阅读卡；空书架诚实空态）

/// 书架页：有书则展示「继续阅读」L2 玻璃卡 + 书目；无书则诚实空态（不伪造书目）。
///
/// 开发包 #5：新增「导入本地 txt」入口（`.fileImporter`，不伪装有书）；书项 `onTap` 用对应章节文本
/// 构建 `ReaderEngine` 并 present `ReaderSurfaceView(engine:)`（内联 overlay，0 玻璃、跨平台）。
/// 导入浮层走系统 `.fileImporter`（非自定义玻璃浮层，故不触碰 `GlassSurface` 白名单）。
struct ShelfScreen: View {
    let bookShelf: BookShelfStore
    /// 当前年龄态（FR-032 ⑥：未成年人模式进度独立存储）。
    var ageState: AgeGateState = .adultConfirmed
    let onOpenReader: () -> Void
    /// 本地检索索引（nil ＝索引不可用，导入仍可完成）。
    let searchStore: LocalSearchStore?

    @State private var showImporter = false
    @State private var activeEngine: ReaderEngine?
    /// 导入被拒原因（FR-034 凭据命中）；nil ＝ 无拒绝。
    @State private var importRejectionMessage: String?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack {
                    Text("书架").font(.title.bold())
                    Spacer()
                    Button(action: { showImporter = true }) {
                        HStack(spacing: 6) { ThemedInkIcon(.download, size: 15); Text("导入本地 txt") }
                    }
                }
                .padding()

                // FR-034：凭据命中导致的导入被拒——如实说明原因（不回显凭据）
                if let rejection = importRejectionMessage {
                    Text(rejection)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
                if bookShelf.items.isEmpty {
                    HonestPlaceholder(screenName: "书架")
                } else {
                    realShelfList
                }
            }

            // 阅读器内联呈现（0 玻璃；跨平台，不依赖 .sheet/.fullScreenCover 语义）
            if let engine = activeEngine {
                ReaderSurfaceView(engine: engine, onExit: { activeEngine = nil },
                                  bookShelf: bookShelf, ageState: ageState)
                    .transition(.identity)
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.plainText],
                      allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        // FR-024a 检索跳转：消费 App 级路由器上的待处理请求。
        // 触发时机两处：onAppear（检索后切到书架 Tab）与 onChange（已在本 Tab 时再检索）。
        // `consume()` 是一次性的，两处都调不会重复打开。
        .onAppear { consumeNavigationRequest() }
        .onReceive(NotificationCenter.default.publisher(for: .readerNavigationRequested)) { _ in
            // 已经在书架 Tab 时，Tab 不会重新 appear；直接消费通知。
            consumeNavigationRequest()
        }
    }

    /// 消费检索投递的打开请求（一次性）。
    private func consumeNavigationRequest() {
        guard let request = ReaderNavigator.shared.consume() else { return }
        guard let item = bookShelf.item(for: request.bookID) else { return }
        let chapterIndex = min(max(0, request.chapterIndex), max(0, item.chapters.count - 1))
        guard let text = bookShelf.chapterText(for: item, chapterIndex: chapterIndex) else { return }
        let typography = TypographyPresetStore().load()
        let engine = ReaderEngine(bookID: item.bookID, chapterID: chapterIndex, chapterText: text,
                                  typography: typography,
                                  containerSize: ReaderLayout.shared.containerSize)
        // 命中偏移已由上游在原始章节二次扫描得到；写入共享进度仓库后，
        // ReaderSurface.prepareSession 会按 charOffset 二分恢复到命中所在页。
        if let offset = request.charOffset {
            engine.recordProgress(at: offset)
        }
        activeEngine = engine
    }

    @ViewBuilder
    private var realShelfList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 继续阅读卡：L2 玻璃（D-28 白名单：继续阅读卡），点击打开该书
                if let resume = bookShelf.items.first(where: { $0.lastReadAnchor != nil }) {
                    ContinueReadingCard(item: resume, onOpen: { openBook(resume) })
                }
                ForEach(bookShelf.items, id: \.bookID) { item in
                    BookRow(item: item, onTap: { openBook(item) },
                            onAbandon: { abandonBook(item) })
                }
            }
            .padding()
        }
    }

    /// 打开某书：取 lastReadAnchor 对应章（无则首章）文本 → 构建引擎 → 呈现。
    ///
    /// 开发包 #8：**按持久化排版预设排版**（`TypographyPresetStore`）——
    /// 用户在「我」页改过字号/行高后，打开书即按新预设渲染（若与引擎当前排版不同，
    /// `ReaderSurfaceView` 会走重排链路，不静默沿用旧排版）。
    ///
    /// 开发包 #10：**容器尺寸取唯一来源** `ReaderLayout.shared`——
    /// 与设置页、阅读器实测值同源 ⇒ 两端签名一致 ⇒ 缓存互通。
    private func openBook(_ item: BookShelfItem) {
        let chapterIndex = min(item.lastReadAnchor?.chapterID ?? 0, max(0, item.chapters.count - 1))
        guard let text = bookShelf.chapterText(for: item, chapterIndex: chapterIndex) else { return }
        let typography = TypographyPresetStore().load()
        activeEngine = ReaderEngine(bookID: item.bookID, chapterID: chapterIndex, chapterText: text,
                                    typography: typography,
                                    containerSize: ReaderLayout.shared.containerSize)
    }

    /// FR-035 手动弃读：从书架移除并清理全部关联数据（进度/书签/划线/检索索引/版本标签）。
    ///
    /// 用 `contextMenu` 长按触发（书架是 ScrollView，非 List，无法用滑动删除）。
    /// **诚实交互**：移除不弹确认框——弃读是明确动作，且数据不可恢复性已在菜单文案体现
    /// （"弃读"是破坏性动词，不是"删除"这种中性词）。
    private func abandonBook(_ item: BookShelfItem) {
        _ = bookShelf.abandon(
            bookID: item.bookID,
            progressStore: ReadingProgressStore(),
            bookmarksStore: BookmarksStore(),
            highlightsStore: HighlightsStore(),
            searchStore: searchStore,
            labelStore: VersionLabelStore()
        )
    }

    /// 处理导入结果：取消则不产生条目（诚实）；凭据命中则拒绝导入；成功则导入并立即打开首章。
    private func handleImport(_ result: Result<[URL], Error>) {
        guard let url = try? result.get().first else { return }   // 取消：不生成条目

        // **FR-034 凭据校验**：导入前静态扫描，命中即拒绝（不落盘、不记录凭据原文）。
        if let data = try? Data(contentsOf: url) {
            let scan = CredentialScanner.scan(data: data)
            if scan.shouldReject {
                importRejectionMessage = scan.rejectionMessage
                return   // 拒绝导入：不生成条目
            }
        }

        let bookID = "local-" + url.lastPathComponent
        let title = url.deletingPathExtension().lastPathComponent
        do {
            let item = try bookShelf.importLocalBook(bookID: bookID, title: title, fileURL: url)
            importRejectionMessage = nil
            // FR-024a：导入成功后显式建立本地 FTS 索引（逐章切片，不一次性常驻全文）。
            // 索引失败不阻断导入/阅读——搜索页走诚实空态，书架仍可用。
            if let searchStore,
               let data = try? Data(contentsOf: url) {
                _ = searchStore.indexBook(bookID: item.bookID, bookTitle: item.title,
                                          fileData: data, chapters: item.chapters)
            }
            openBook(item)
        } catch {
            // 导入失败（如沙箱拒绝）：不产生条目，保持诚实空态
        }
    }
}

/// 继续阅读卡：L2 玻璃，由真实 `lastReadAnchor`（ReadingProgress，4 字段无 pageIndex）驱动。
private struct ContinueReadingCard: View {
    let item: BookShelfItem
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            GlassSurface(strength: .l2, interactive: true) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("继续阅读").font(.footnote).foregroundStyle(.secondary)
                    Text(item.title).font(.headline)
                    if let anchor = item.lastReadAnchor {
                        Text("第 \(anchor.chapterID) 章 · 进度 \(anchor.charOffset) 字")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        }
        .buttonStyle(.plain)
    }
}

private struct BookRow: View {
    let item: BookShelfItem
    let onTap: () -> Void
    /// FR-035 弃读：长按菜单（ScrollView 内无法用 List 滑动删除，contextMenu 是自然形态）。
    var onAbandon: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // FR-007：封面（有则真封面，无则配色占位——不用第三方书封）
                BookCoverView(title: item.title, coverData: item.coverImageData)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.subheadline.weight(.medium))
                    // FR-007：导入即显示作者（无作者时不显示这一行，诚实空态）
                    if let author = item.author, !author.isEmpty {
                        Text("\(author) · \(item.chapterCount) 章")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("\(item.chapterCount) 章 · \(item.source == .localImport ? "本地导入" : "在线")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(12)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: onAbandon) {
                HStack(spacing: 6) { ThemedInkIcon(.trash, size: 15); Text("弃读") }
            }
        }
        .accessibilityAction(named: "弃读") { onAbandon() }
    }
}

// MARK: - 我（年龄状态条由矩阵派生；无任何切换控件）

struct MeScreen: View {
    let ageState: AgeGateState
    let variant: BuildVariant

    /// 书架仓库（开发包 #8：重排作用于**当前真实书**；nil ＝ 无书 → 诚实空态）。
    let bookShelf: BookShelfStore?

    /// 当前排版预设：由持久化存储加载（首次为 `ReaderTypography.default`），改动即时落盘。
    @State private var preset: ReaderTypography
    /// 动效开关（FR-030 原文②）：全局总关 ＋ 每 ID 一行独立开关；由持久化存储加载。
    @State private var motionSettings: MotionSettings
    /// 当前书的重排会话（持有协调器；跨点击复用签名 → 可观察「排版未变／已重排」）。
    @State private var bookSession: ReaderSession?
    /// 最近一次重排的用户可读反馈（诚实空态：无可重排内容时如实说明，**不伪装成功**）。
    @State private var repaginationFeedback: String = ""
    /// 后台重排状态模型（调度在后台线程、状态在主线程呈现）。
    @StateObject private var backgroundModel = RepaginationStatusModel()
    /// 动效运行时面板是否呈现（开发包 #9/#10：13 个动效的真实可播实现 ＋ 真实触发点）。
    @State private var showMotionRuntime = false
    /// 版权投诉表单是否呈现（FR-033 P0 合规基座：设置内常驻入口）。
    @State private var showComplaint = false
    /// 备份与恢复视图是否呈现（FR-025 设置与数据）。
    @State private var showBackup = false
    /// 主题状态（FR-010）：皮肤 + 夜航对比档 + 切换模式。
    @State private var themeState: ThemeState = ThemeStore().load()
    /// FR-028 皮肤包：三套主题皮肤（四项联动）。
    @State private var skinStore = ThemeSkinStore()
    /// FR-028 方案分享界面。
    @State private var showSchemeSharing = false
    @State private var currentSkin: ThemeSkinSpec.Skin = ThemeSkinStore().skin
    /// FR-028 第 ④ 项：主题切换转场（色带漫延）。
    @StateObject private var wipe = ThemeWipeController.shared
    /// FR-032 ③④：监护会话（**跨页面共享**；此前是 @State，视图重建会重载并重置锁定计数）。
    @StateObject private var guardianSession = GuardianSession.shared
    /// FR-032 ③：验证输入与反馈。
    @State private var guardianInput = ""
    @State private var guardianMessage = ""
    /// FR-032 ④：家长内容确认（进入时列出书架 N 本）。
    @State private var parentalDecision = ParentalContentDecision()
    /// FR-032 ④：修改隐藏清单的验证输入（凭据本身在 `guardianSession` 里共享）。
    @State private var hiddenAuthInput = ""
    @State private var hiddenAuthMessage = ""

    /// 场景相位：`scenePhase != .active` 立即停后台重排
    /// （对齐 NFR-04「`scenePhase != .active` 立即 `cancelAllTasks()`」的纪律精神）。
    @Environment(\.scenePhase) private var scenePhase

    init(ageState: AgeGateState, variant: BuildVariant, bookShelf: BookShelfStore? = nil) {
        self.ageState = ageState
        self.variant = variant
        self.bookShelf = bookShelf
        _preset = State(initialValue: TypographyPresetStore().load())
        _motionSettings = State(initialValue: MotionSettingsStore().load())
    }

    var body: some View {
        List {
            Section {
                // 视图层只读矩阵（AGE_MATRIX §3：视图层出现 if state == .xxx 拼接文案即判不通过）
                if let banner = AgeGateMatrix.bannerText(state: ageState, variant: variant) {
                    AgeStateBar(text: banner)
                }
            } header: {
                Text("年龄状态（由 AGE_MATRIX 按 (state, variant) 派生）")
            } footer: {
                Text("切换年龄态不存在任何界面控件——状态由系统分龄决定，保守方向出错是少保护。")
            }

            // 设置入口（开发包 #6/#7/#8）：受控项经 AgeGateMatrix.cell(.settingsPath) 派生可见性；
            // .absent 态结构上不生成（沉默，非隐藏）。排版预设已持久化，动效开关已持久化，无年龄切换控件。
            if AgeGateMatrix.cell(state: ageState, variant: variant).settingsPath != .absent {
                settingsSection
                repaginationSection
                motionSection
                // FR-033 版权声明与投诉（P0 合规基座）：设置内**常驻入口**。
                Section {
                    Button {
                        showComplaint = true
                    } label: {
                        HStack(spacing: 6) { ThemedInkIcon(.shield, size: 15); Text("版权声明与投诉") }
                    }
                } footer: {
                    Text("投诉通达邮箱为占位（发行前必须替换，发布闸门 A9/A10 不可豁免）；受理回执 48h，处理 15 工作日。")
                }

                // FR-010 夜间与主题：皮肤 + 夜航对比档（两档制）+ 切换模式
                Section {
                    Picker("主题", selection: Binding(
                        get: { themeState.skin },
                        set: { themeState.skin = $0; themeState.mode = .manual; saveTheme() }
                    )) {
                        Text("雪纸").tag(ThemeSkin.snowPaper)
                        Text("夜航").tag(ThemeSkin.nightVoyage)
                    }
                    Picker("夜航对比", selection: Binding(
                        get: { themeState.nightContrast },
                        set: { themeState.nightContrast = $0; saveTheme() }
                    )) {
                        Text("标准（5.4:1）").tag(NightContrast.standard)
                        Text("高对比（13:1）").tag(NightContrast.highContrast)
                    }
                    .disabled(themeState.skin == .snowPaper)
                    Picker("切换方式", selection: Binding(
                        get: { themeState.mode },
                        set: { themeState.mode = $0; saveTheme() }
                    )) {
                        Text("按时段（22:00–6:00 夜航）").tag(ThemeMode.byTime)
                        Text("手动").tag(ThemeMode.manual)
                    }
                } header: {
                    Text("夜间与主题")
                } footer: {
                    Text("夜航两档制：标准 #8A8A8A（5.4:1）／高对比 #CFCDC7（13:1），不设第三档。高对比是夜航的色值档位，不是独立主题。")
                }

                // FR-032 ③④：未成年人模式的监护入口（**仅 .minorConfirmed 出现**）。
                if ageState == .minorConfirmed {
                    guardianSection
                }

                // FR-028 皮肤包：三套主题（DESIGN §3.1 四项联动：图标/强调色/玻璃/转场）
                Section {
                    ForEach(ThemeSkinSpec.Skin.allCases, id: \.rawValue) { skin in
                        Button {
                            try? skinStore.setSkin(skin)
                            currentSkin = skin
                            // **FR-028 第 ④ 项**：换皮肤即播色带漫延转场（配色取新皮肤）
                            wipe.wipe(to: ThemeSkinSpec.spec(for: skin))
                        } label: {
                            HStack {
                                // 强调色圆点（第 ② 项：强调色随主题变）
                                Circle()
                                    .fill(Color(hexString: ThemeSkinSpec.spec(for: skin).accentHex))
                                    .frame(width: 16, height: 16)
                                Text(skin.displayName)
                                Spacer()
                                if currentSkin == skin {
                                    ThemedInkIcon(.check, size: 15)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("主题皮肤")
                } footer: {
                    Text("换主题时图标描边与端点、强调色、玻璃 tint 与色散、转场配色四项同时变——任一项不随主题动即判未完成。")
                }

                // FR-028 方案分享：把当前皮肤+排版+动效存为方案并分享
                Section {
                    Button {
                        showSchemeSharing = true
                    } label: {
                        HStack(spacing: 6) {
                            ThemedInkIcon(.upload, size: 15)
                            Text("阅读方案")
                        }
                    }
                } footer: {
                    Text("把当前的皮肤、排版与动效存为方案，可分享给他人或在其他设备导入。方案不含书籍内容。")
                }
                .sheet(isPresented: $showSchemeSharing) {
                    SchemeSharingView(typography: preset,
                                      motion: motionSettings,
                                      skin: currentSkin,
                                      onClose: { showSchemeSharing = false })
                }

                // FR-025 备份与恢复（设置与数据）：导出进度与偏好，不含正文。
                Section {
                    Button {
                        showBackup = true
                    } label: {
                        HStack(spacing: 6) { ThemedInkIcon(.drive, size: 15); Text("备份与恢复") }
                    }
                } footer: {
                    Text("导出阅读进度、排版与动效偏好（不含任何书籍正文）；格式带版本号，旧备份可迁移。")
                }
            }
        }
        // 动效运行时面板（开发包 #9/#10）：13 个动效的真实可播实现 ＋ 真实触发点。
        // 内联 overlay 呈现（跨平台；**不用系统 sheet morph**——可关转场禁用系统 push/sheet morph）。
        .overlay {
            if showMotionRuntime {
                MotionRuntimeScreen()
                    .transition(.identity)
            }
        }
        // 版权投诉表单（FR-033）：表单是信息承载，走系统 sheet（非玻璃白名单容器）。
        .sheet(isPresented: $showComplaint) {
            CopyrightComplaintView()
        }
        // FR-025 备份与恢复
        .sheet(isPresented: $showBackup) {
            BackupView(service: BackupService())
        }
        // 预设改动即时落盘（单门 JSON 原子写；不设备份排除键——用户偏好应可备份）
        .onChange(of: preset) { try? TypographyPresetStore().save(preset) }
        // 进入设置页时把持久化的动效开关应用到唯一动画入口
        // （否则「持久化」只是落盘不生效＝不诚实）
        .onAppear { MotionCoordinator.shared.apply(motionSettings) }
        // `scenePhase != .active` 立即停后台重排（NFR-04 纪律精神）
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { backgroundModel.cancel() }
        }
    }

    /// 设置（持久化排版预设）：真实可编辑，改动经 `.onChange` 即时落盘。
    @ViewBuilder
    private var settingsSection: some View {
        Section {
            // **档位制（FR-009）**：离散档位，不是滑块——PRD 明文给出的可选项只有三档。
            // 旧实现用 Slider(14...28) 允许任意值，开放了 PRD 明令禁止的档位（含 12pt 以下）。

            // 字号：19 / 20（默认）/ 21 pt
            Picker("字号", selection: Binding(
                get: { TypographyTiers.normalizeFontSize(preset.fontSize) },
                set: { size in
                    preset.fontSize = size
                    // 缩进随字号联动（2×字号）：缩进开启时同步更新
                    if preset.indent > 0 { preset.indent = size * 2 }
                }
            )) {
                ForEach(TypographyTiers.fontSizes, id: \.self) { size in
                    Text("\(Int(size)) pt").tag(size)
                }
            }
            .pickerStyle(.segmented)

            // 行高：1.70 / 1.75（默认）/ 1.85（行盒 min==max==字号×倍数，D-31）
            Picker("行高", selection: Binding(
                get: { TypographyTiers.normalizeLineHeight(preset.lineHeightMultiplier) },
                set: { preset.lineHeightMultiplier = $0 }
            )) {
                ForEach(TypographyTiers.lineHeights, id: \.self) { lh in
                    Text(String(format: "%.2f", lh)).tag(lh)
                }
            }
            .pickerStyle(.segmented)

            // 边距：16 / 20（默认）/ 24 pt（左右对称）
            Picker("边距", selection: Binding(
                get: { TypographyTiers.normalizeMargin(preset.insets.leading) },
                set: { m in
                    preset.insets.leading = m
                    preset.insets.trailing = m
                }
            )) {
                ForEach(TypographyTiers.margins, id: \.self) { m in
                    Text("\(Int(m)) pt").tag(m)
                }
            }
            .pickerStyle(.segmented)

            // 首行缩进：无 / 2 字（= 2×字号）
            Picker("首行缩进", selection: Binding(
                get: { preset.indent > 0 },
                set: { preset.indent = TypographyTiers.indent(enabled: $0, fontSize: preset.fontSize) }
            )) {
                Text("无").tag(false)
                Text("2 字").tag(true)
            }
            .pickerStyle(.segmented)

            // 段前/段后：**固定值，不是用户可调项**（PRD 正文样式基线：段前 12、段后 0）
            LabeledContent("段前间距", value: "\(Int(TypographyTiers.paragraphSpacingBefore)) pt（固定）")
            LabeledContent("段后间距", value: "\(Int(TypographyTiers.paragraphSpacingAfter)) pt（固定）")

            // 重排入口在下方「阅读重排」分区（开发包 #8：作用于当前真实书）——
            // **替换** #6 的「应用并重分页（演示）」，不保留两个语义重复的按钮。

            Text("排版预设已持久化（Application Support/com.inksight/preset/TypographyPreset.json），随备份恢复；改参数即时落盘、下次启动自动恢复。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("本页无任何「切换年龄 / 完善年龄」控件——那是合规反向路径，本包不实现（D-03）。")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("阅读排版设置（持久化预设）")
        } footer: {
            Text("排版预设只存 8 个排版参数（无正文、无页码）；重排只在内存完成（CTFrameCache 仅内存，不落盘）。")
        }
    }

    /// 阅读重排分区（开发包 #8）：作用于**当前真实书**，不再是演示章节。
    ///
    /// - 「重排当前章」：读出当前书当前章正文 → 真实 `apply()` → **用户可读反馈**；
    /// - 「其余章后台重排」：入队（**只存取正文的闭包**）＋ 调度器驱动（1 章/次，可取消）；
    /// - **诚实空态**：无当前书／正文取不到／只有 1 章时，如实说明「无可重排内容」，**不伪装成功**。
    @ViewBuilder
    private var repaginationSection: some View {
        Section {
            // 当前书信息（诚实：没有书就明说，不伪造书目）
            if let item = currentBookItem {
                HStack {
                    Text("当前书")
                    Spacer()
                    Text("\(item.title) · \(item.chapterCount) 章").foregroundStyle(.secondary)
                }
            } else {
                Text("当前书：无（书架为空或未注入）")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button(action: repaginateCurrentChapter) {
                Text("重排当前章（当前书）")
            }

            if !repaginationFeedback.isEmpty {
                Text(repaginationFeedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: startBackgroundRepagination) {
                Text("其余章后台重排")
            }

            if !backgroundModel.statusText.isEmpty {
                Text(backgroundModel.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if backgroundModel.scheduler.isRunning {
                Button(action: { backgroundModel.cancel() }) {
                    Text("取消后台重排")
                }
            }
        } header: {
            Text("阅读重排（当前书）")
        } footer: {
            Text("后台重排按「1 章/次」增量处理，正文按需切片读取、常驻 ≤1 章，可随时取消；不涉及任何正文落盘。")
        }
    }

    /// 动效分区（开发包 #7 · FR-030 原文②）：按「转场 4／彩蛋 5／手势 2」三组分组，
    /// **每 ID 一行独立开关**。行上中文名取自 `MotionRegistry.spec(for:).chineseName`
    /// ——**Registry 是唯一来源，UI 不另写一份名字**。
    ///
    /// **T4／T5 无单独开关**（FR-030 明文：T4 直切回位＋位置标签、T5 降级 0ms 静态成功态）
    /// → `MotionRegistry.ids(inGroup:)` 已将其剔除，此处**结构上不生成**这两行开关。
    @ViewBuilder
    private var motionSection: some View {
        // 全局总开关（FR-030）：优先级最高——关闭后任何单个动效开关都不能让它重新播放。
        Section {
            Toggle(isOn: Binding(
                get: { motionSettings.globalEnabled },
                set: { newValue in
                    motionSettings.globalEnabled = newValue
                    applyMotionSettings()
                }
            )) {
                Text("全部动效")
            }
        } header: {
            Text("动效总开关")
        } footer: {
            Text("总关优先级最高：关闭后，任何单个动效开关都不能让它重新播放。关闭只减掉动画，不减掉功能。")
        }

        ForEach(MotionGroup.allCases, id: \.self) { group in
            Section {
                ForEach(MotionRegistry.ids(inGroup: group), id: \.self) { id in
                    Toggle(isOn: Binding(
                        get: { motionSettings.perID[id.rawValue] ?? true },
                        set: { newValue in
                            motionSettings.perID[id.rawValue] = newValue
                            applyMotionSettings()
                        }
                    )) {
                        HStack {
                            Text(MotionRegistry.spec(for: id).chineseName)
                            Spacer()
                            Text(id.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(group.chineseName)
            }
        }

        // 动效运行时面板入口（开发包 #9/#10）：13 个动效的**真实可播实现** ＋ 真实触发点。
        Section {
            Button(action: { showMotionRuntime = true }) {
                Text("动效运行时（13 个动效可播）")
            }
            Text("开关只决定「播不播」；每个动效的真实触发点都在运行时面板里（触发一律经 MotionCoordinator.perform）。")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("动效运行时")
        }
    }

    /// FR-032 ③④ 监护段：家长内容确认 ＋ 监控验证退出（**模式内不出现书源/网络能力**）。
    @ViewBuilder
    private var guardianSection: some View {
        Section {
            // ④ 家长内容确认：列出书架 N 本，全部保留 / 仅保留指定
            LabeledContent("书架图书", value: "\(bookShelf?.items.count ?? 0) 本")
            Toggle("全部保留", isOn: Binding(
                get: { parentalDecision.keepAll },
                set: { parentalDecision.keepAll = $0 }
            ))
            if !parentalDecision.keepAll {
                ForEach(bookShelf?.items ?? [], id: \.bookID) { item in
                    Toggle(item.title, isOn: Binding(
                        get: { parentalDecision.keptBookIDs.contains(item.bookID) },
                        set: { on in
                            if on { parentalDecision.keptBookIDs.insert(item.bookID) }
                            else { parentalDecision.keptBookIDs.remove(item.bookID) }
                        }
                    ))
                }
            }
            // FR-032 ④：隐藏清单修改**必须经监护验证**（类型层强制：setHidden 需 GuardianProof）
            LabeledContent("家长隐藏", value: "\(parentalDecision.hiddenBookIDs.count) 本")
            if !guardianSession.hasValidProof {
                SecureField("输入监护验证码以修改隐藏清单", text: $hiddenAuthInput)
                Button("验证") {
                    if guardianSession.verifyAndAuthorize(hiddenAuthInput) != nil {
                        hiddenAuthInput = ""
                        hiddenAuthMessage = "验证通过（5 分钟内有效，跨页面共享）。"
                    } else {
                        hiddenAuthMessage = "验证码不正确或已锁定。"
                    }
                }
                .disabled(hiddenAuthInput.isEmpty)
            } else {
                Text("已验证，可选择隐藏的书")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(bookShelf?.items ?? [], id: \.bookID) { item in
                    Toggle("隐藏：\(item.title)", isOn: Binding(
                        get: { parentalDecision.hiddenBookIDs.contains(item.bookID) },
                        set: { on in
                            // 无凭据时 setHidden 返回 false（类型层拒绝修改）
                            let changed = parentalDecision.setHidden(item.bookID, hidden: on,
                                                                    authorizedBy: guardianSession.currentProof())
                            hiddenAuthMessage = changed ? "" : "修改被拒绝：需监护验证"
                        }
                    ))
                }
            }
            if !hiddenAuthMessage.isEmpty {
                Text(hiddenAuthMessage).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("家长内容确认")
        } footer: {
            Text("隐藏清单对孩子不可见、不可撤销；仅监护验证后可修改（验证 5 分钟内有效）。")
        }

        Section {
            // ③ 监护验证：未成年模式不可自行退出
            if guardianSession.verification.isConfigured {
                SecureField("监护验证码", text: $guardianInput)
                Button("验证并退出未成年人模式") {
                    switch guardianSession.verification.verify(guardianInput) {
                    case .success:
                        // FR-032 ⑥：验证通过 → **自动合并**模式内进度回主进度
                        // （时间戳为准、两份都保留、不弹选择框），成功后清空模式内副本。
                        do {
                            let outcome = try MinorModeExitCoordinator.exit(
                                code: guardianInput,
                                verification: guardianSession.verification,
                                minorStore: MinorModeProgressStore(),
                                mainStore: ReadingProgressStore())
                            if let report = outcome.report {
                                guardianMessage =
                                    "已验证并退出。进度已自动合并："
                                    + "采用模式内 \(report.tookMinorProgress.count) 本，"
                                    + "保留主进度 \(report.keptMainProgress.count) 本。"
                            } else {
                                guardianMessage = "验证未通过，未合并。"
                            }
                        } catch {
                            guardianMessage = "合并失败：\(error)"
                        }
                        guardianInput = ""
                    case .wrongCode:
                        guardianMessage = "验证码不正确。"
                    case .lockedOut(let remaining):
                        guardianMessage = "尝试次数过多，请 \(remaining) 秒后重试。"
                    case .notConfigured:
                        guardianMessage = "尚未设置验证码。"
                    }
                }
                if !guardianMessage.isEmpty {
                    Text(guardianMessage).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Button("设置监护验证码") {
                    do {
                        // FR-032 ③：明文立即哈希后丢弃，只落盘加盐迭代摘要（重启后仍有效）。
                        try guardianSession.verification.setCode(guardianInput)
                        guardianInput = ""
                        guardianMessage = "验证码已设置并保存（仅存加盐摘要，不留明文）。"
                    } catch {
                        guardianMessage = "验证码保存失败，请重试。"
                    }
                }
                .disabled(guardianInput.isEmpty)
                SecureField("输入要设置的验证码", text: $guardianInput)
                if !guardianMessage.isEmpty {
                    Text(guardianMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("监护验证")
        } footer: {
            Text("未成年人模式不可自行退出，需监护验证码。验证码只存加盐哈希，不落明文、不进日志。")
        }
    }

    /// 主题状态即时落盘（单门 JSON 原子写）。
    private func saveTheme() {
        try? ThemeStore().save(themeState)
    }

    /// 把动效开关应用到唯一动画入口（`MotionCoordinator`），并即时落盘（单门 JSON 原子写）。
    @MainActor
    private func applyMotionSettings() {
        MotionCoordinator.shared.apply(motionSettings)
        try? MotionSettingsStore().save(motionSettings)
    }

    // MARK: - 阅读重排（开发包 #8：真实链路）

    /// 当前书（继续阅读优先：有阅读锚点的优先，否则取第一本）。
    private var currentBookItem: BookShelfItem? {
        bookShelf?.currentItem
    }

    /// 当前书当前章索引（有阅读锚点则用锚点指向的章，越界回退到首章）。
    private func currentChapterIndex(of item: BookShelfItem) -> Int {
        let anchorChapter = item.lastReadAnchor?.chapterID ?? 0
        return min(anchorChapter, max(0, item.chapters.count - 1))
    }

    /// 重排当前书当前章（真实链路）：读正文 → 真实 `apply()` → 用户可读反馈。
    ///
    /// **诚实空态**：无当前书或正文取不到时，如实说明「无可重排内容」，**不伪装成功**。
    private func repaginateCurrentChapter() {
        // 落盘（.onChange 已落，这里显式再保一次一致性）
        try? TypographyPresetStore().save(preset)

        guard let item = currentBookItem else {
            repaginationFeedback = "无可重排内容：书架里没有书。"
            return
        }
        let chapterIndex = currentChapterIndex(of: item)
        guard let shelf = bookShelf,
              let text = shelf.chapterText(for: item, chapterIndex: chapterIndex),
              !text.isEmpty else {
            // 降级门面（D-15）：章节正文取不到 → chapterLoadFailed（清单登记 declaresData=false，
            // 「本章加载失败」+ 原因 + 重试）。门面只登记事件，UI 文案仍由本处诚实空态给出。
            _ = Degradation.degrade(kind: .chapterLoadFailed, declaresData: false,
                                    detail: "重排当前章：正文取不到（书=\(item.title) 章=\(chapterIndex)）")
            repaginationFeedback = "无可重排内容：当前书的章节正文不可读。"
            return
        }

        // 会话复用（同一本书同一章时保留签名 → 可观察「排版未变／已重排」）
        let session: ReaderSession
        if let existing = bookSession,
           existing.engine?.bookID == item.bookID,
           existing.engine?.chapterID == chapterIndex {
            session = existing
        } else {
            session = ReaderSession(engine: ReaderEngine(bookID: item.bookID,
                                                        chapterID: chapterIndex,
                                                        chapterText: text,
                                                        typography: preset,
                                                        containerSize: ReaderLayout.shared.containerSize),
                                    coordinator: .shared)
            bookSession = session
        }
        let outcome = session.applyTypography(preset,
                                              containerSize: ReaderLayout.shared.containerSize,
                                              screenScale: ReaderLayout.shared.screenScale)
        repaginationFeedback = outcome.message
    }

    /// 其余章后台重排：入队（**只存取正文的闭包**）＋ 调度器驱动（1 章/次，可取消）。
    ///
    /// **诚实空态**：无当前书／只有 1 章时，如实说明「无可重排内容」。
    private func startBackgroundRepagination() {
        guard let item = currentBookItem else {
            backgroundModel.statusText = "无可重排内容：书架里没有书。"
            return
        }
        guard let shelf = bookShelf else {
            backgroundModel.statusText = "无可重排内容：未注入书架。"
            return
        }
        let currentIndex = currentChapterIndex(of: item)
        // 其余章：**只提供取正文的闭包**——正文不在入队时物化（NFR-09 ②，常驻正文 ≤1 章）
        let chapters: [(id: Int, textProvider: () -> String?)] = item.chapters.indices
            .filter { $0 != currentIndex }
            .map { index in
                (id: index, textProvider: { shelf.chapterText(for: item, chapterIndex: index) })
            }
        guard !chapters.isEmpty else {
            backgroundModel.statusText = "无可重排内容：当前书只有 1 章，没有其余章可后台重排。"
            return
        }
        backgroundModel.start(chapters: chapters,
                              typography: preset,
                              containerSize: ReaderLayout.shared.containerSize,
                              screenScale: ReaderLayout.shared.screenScale)
    }
}
