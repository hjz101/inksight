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
            Image(systemName: "tray")
                .font(.system(size: 40))
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("墨量").font(.title.bold())

                // FR-024a 本地全文检索入口（检索面：墨量 Tab，PRD §2.0）
                Button {
                    showSearch = true
                } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("在本地书里找一句话")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                GlassSurface(strength: .l2, interactive: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("阅读成就").font(.headline)
                        Text("已导入 \(bookShelf.items.count) 本书")
                            .font(.subheadline)
                        // 每日阅读时长上限：以家长侧设置为准。
                        // 注意：不引用 DailyReadingQuota.minutesTBD 的裸值——D-03 无依据不造数，且不 force-unwrap。
                        Text("每日阅读时长上限：以家长侧设置为准")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
            }
            .padding()
        }
        .sheet(isPresented: $showSearch) {
            LocalSearchView(searchStore: searchStore)
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
    let onOpenReader: () -> Void

    @State private var showImporter = false
    @State private var activeEngine: ReaderEngine?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack {
                    Text("书架").font(.title.bold())
                    Spacer()
                    Button(action: { showImporter = true }) {
                        Label("导入本地 txt", systemImage: "square.and.arrow.down")
                    }
                }
                .padding()

                if bookShelf.items.isEmpty {
                    HonestPlaceholder(screenName: "书架")
                } else {
                    realShelfList
                }
            }

            // 阅读器内联呈现（0 玻璃；跨平台，不依赖 .sheet/.fullScreenCover 语义）
            if let engine = activeEngine {
                ReaderSurfaceView(engine: engine, onExit: { activeEngine = nil })
                    .transition(.identity)
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.plainText],
                      allowsMultipleSelection: false) { result in
            handleImport(result)
        }
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
                    BookRow(item: item, onTap: { openBook(item) })
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

    /// 处理导入结果：取消则不产生条目（诚实）；成功则导入并立即打开首章（演示闭环）。
    private func handleImport(_ result: Result<[URL], Error>) {
        guard let url = try? result.get().first else { return }   // 取消：不生成条目
        let bookID = "local-" + url.lastPathComponent
        let title = url.deletingPathExtension().lastPathComponent
        do {
            let item = try bookShelf.importLocalBook(bookID: bookID, title: title, fileURL: url)
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

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.subheadline.weight(.medium))
                    Text("\(item.chapterCount) 章 · \(item.source == .localImport ? "本地导入" : "在线")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
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
                        Label("版权声明与投诉", systemImage: "exclamationmark.shield")
                    }
                } footer: {
                    Text("投诉通达邮箱为占位（发行前必须替换，发布闸门 A9/A10 不可豁免）；受理回执 48h，处理 15 工作日。")
                }

                // FR-025 备份与恢复（设置与数据）：导出进度与偏好，不含正文。
                Section {
                    Button {
                        showBackup = true
                    } label: {
                        Label("备份与恢复", systemImage: "externaldrive")
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
            // 字号
            HStack {
                Text("字号")
                Spacer()
                Text("\(Int(preset.fontSize)) pt").foregroundStyle(.secondary)
            }
            Slider(value: $preset.fontSize, in: 14...28, step: 1)

            // 行高倍数
            HStack {
                Text("行高倍数")
                Spacer()
                Text(String(format: "%.2f", preset.lineHeightMultiplier)).foregroundStyle(.secondary)
            }
            Slider(value: $preset.lineHeightMultiplier, in: 1.2...2.4, step: 0.05)

            // 正文左右内边距（leading / trailing 同步，保持对称）
            HStack {
                Text("正文左右内边距")
                Spacer()
                Text("\(Int(preset.insets.leading)) pt").foregroundStyle(.secondary)
            }
            Slider(value: Binding(
                get: { preset.insets.leading },
                set: { v in
                    preset.insets.leading = v
                    preset.insets.trailing = v
                }
            ), in: 8...48, step: 1)

            // 段前 / 段后间距
            Stepper(value: $preset.paragraphSpacingBefore, in: 0...24, step: 1) {
                Text("段前间距：\(Int(preset.paragraphSpacingBefore)) pt")
            }
            Stepper(value: $preset.paragraphSpacingAfter, in: 0...24, step: 1) {
                Text("段后间距：\(Int(preset.paragraphSpacingAfter)) pt")
            }

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
