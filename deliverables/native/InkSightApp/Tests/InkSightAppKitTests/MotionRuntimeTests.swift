import XCTest
@testable import InkSightAppKit
import InkSightCore
import Foundation

/// 开发包 #9／#10 契约测试：
/// 13 个动效的运行时接线（逐 ID）＋ T4／T5 反馈保留 ＋ UIT2 模式注册 ＋ EGG5 限流停跑
/// ＋ 材质插值守卫 ＋ 系统「减弱动态效果」 ＋ **容器尺寸贯通** ＋ **单例由构造保证**。
final class MotionRuntimeTests: XCTestCase {

    /// 确定性示例章节（供重排/签名测试用）。
    private func sampleChapter() -> String {
        let para = "墨见读书专注于本地阅读，动效与排版各行其道，定位铁律永不动摇。"
        return (0..<12).map { _ in para }.joined(separator: "\n")
    }

    // MARK: - 逐 ID 契约（每个 ID 一条）

    /// 逐 ID 契约的统一断言：
    /// ① **总关** → 该 ID 走不播动画路径（`keepTrigger`：功能仍在）**或**连触发短路（`dropTrigger`）；
    /// ② **单关该 ID** → 同上；
    /// ③ **其余 ID 不受影响**（逐 ID 隔离）。
    @MainActor
    private func assertPerIDContract(_ id: MotionID,
                                     file: StaticString = #filePath,
                                     line: UInt = #line) {
        // 触发是否应执行，由 Registry 锁定的 `triggerPolicy` 决定（不得擅自改）
        let expectTriggerRuns: Bool
        switch MotionRegistry.spec(for: id).triggerPolicy {
        case .keepTrigger: expectTriggerRuns = true
        case .dropTrigger: expectTriggerRuns = false
        }

        // ① 总关
        let off = MotionCoordinator(isMotionEnabled: false)
        XCTAssertFalse(off.isEnabled(id), "\(id) 总关后必须失效", file: file, line: line)
        XCTAssertNil(off.animation(for: id), "\(id) 总关后必须走不播动画路径", file: file, line: line)
        var firedOff = false
        off.perform(id) { firedOff = true }
        XCTAssertEqual(firedOff, expectTriggerRuns,
                       "\(id) 总关下的触发行为不符（须服从 triggerPolicy）", file: file, line: line)

        // ② 单关该 ID
        let single = MotionCoordinator()
        single.setEnabled(false, for: id)
        XCTAssertFalse(single.isEnabled(id), "\(id) 单关后必须失效", file: file, line: line)
        XCTAssertNil(single.animation(for: id), "\(id) 单关后必须走不播动画路径", file: file, line: line)
        var firedSingle = false
        single.perform(id) { firedSingle = true }
        XCTAssertEqual(firedSingle, expectTriggerRuns,
                       "\(id) 单关下的触发行为不符", file: file, line: line)

        // ③ 其余 ID 不受影响
        for other in MotionID.allCases where other != id {
            XCTAssertTrue(single.isEnabled(other), "\(other) 不应受 \(id) 单关影响", file: file, line: line)
            XCTAssertNotNil(single.animation(for: other),
                            "\(other) 动画不应受 \(id) 单关影响", file: file, line: line)
        }
    }

    @MainActor
    func testT1BookOpenContract() { assertPerIDContract(.t1BookOpen) }
    @MainActor
    func testT2VersionSwapContract() { assertPerIDContract(.t2VersionSwap) }
    @MainActor
    func testT3ThemeWipeContract() { assertPerIDContract(.t3ThemeWipe) }
    @MainActor
    func testT4RestoreSettleContract() { assertPerIDContract(.t4RestoreSettle) }
    @MainActor
    func testT5SwitchRippleContract() { assertPerIDContract(.t5SwitchRipple) }
    @MainActor
    func testT6InkGrowContract() { assertPerIDContract(.t6InkGrow) }
    @MainActor
    func testEGG1CoverLiquidContract() { assertPerIDContract(.egg1CoverLiquid) }
    @MainActor
    func testEGG2PinchSpineContract() { assertPerIDContract(.egg2PinchSpine) }
    @MainActor
    func testEGG3PaperPullContract() { assertPerIDContract(.egg3PaperPull) }
    @MainActor
    func testEGG4DogEarContract() { assertPerIDContract(.egg4DogEar) }
    @MainActor
    func testEGG5ShakePanelContract() { assertPerIDContract(.egg5ShakePanel) }
    @MainActor
    func testUIT1ChromeToggleContract() { assertPerIDContract(.uit1ChromeToggle) }
    @MainActor
    func testUIT2EdgeBackContract() { assertPerIDContract(.uit2EdgeBack) }

    // MARK: - T4／T5 专项（无独立开关，但反馈必须留）

    /// T4／T5：**无独立开关**（FR-030 明文），随总关降级为「直切回位＋位置标签」／「0ms 静态成功态」——
    /// **反馈必须留，动画不必播**。
    @MainActor
    func testT4AndT5HaveNoIndependentSwitchButRetainFeedback() {
        for id in [MotionID.t4RestoreSettle, .t5SwitchRipple] {
            XCTAssertFalse(MotionRegistry.perIDSwitchableIDs.contains(id), "\(id) 无独立开关")
            XCTAssertFalse(MotionEffectCatalog.descriptor(for: id).hasIndependentSwitch,
                           "\(id) 无独立开关")
            XCTAssertEqual(MotionEffectCatalog.descriptor(for: id).offState, .keepFeedback,
                           "\(id) 关态属「反馈必须留」")
            XCTAssertNotNil(MotionEffectCatalog.descriptor(for: id).retainedFeedback,
                            "\(id) 关态必须保留反馈")
        }
        // T4：位置标签；T5：静态成功态
        guard case .positionLabel = MotionEffectCatalog.descriptor(for: .t4RestoreSettle).retainedFeedback else {
            XCTFail("T4 关态应保留位置标签"); return
        }
        guard case .staticSuccess = MotionEffectCatalog.descriptor(for: .t5SwitchRipple).retainedFeedback else {
            XCTFail("T5 关态应保留静态成功态"); return
        }
        // 总关时**触发仍执行**（功能不减——反馈必须留），但**动画不在**
        let off = MotionCoordinator(isMotionEnabled: false)
        var firedT4 = false
        off.perform(.t4RestoreSettle) { firedT4 = true }
        XCTAssertTrue(firedT4, "T4 总关后位置记忆反馈仍必须生效")
        var firedT5 = false
        off.perform(.t5SwitchRipple) { firedT5 = true }
        XCTAssertTrue(firedT5, "T5 总关后静态成功态仍必须生效")
        XCTAssertNil(off.animation(for: .t4RestoreSettle))
        XCTAssertNil(off.animation(for: .t5SwitchRipple))
    }

    // MARK: - UIT2 专项（仅滚动/直切模式注册）

    /// UIT2：**仅滚动/直切模式注册**；仿真（`flip`／`curl`）下**不注册**。
    /// 其余 12 个 ID 在全部模式下都注册。
    @MainActor
    func testUIT2RegistersOnlyInScrollAndDirectModes() {
        for mode in [PageTurnMode.none, .scroll, .vertical] {
            XCTAssertTrue(MotionEffectCatalog.isRegistered(.uit2EdgeBack, in: mode),
                          "\(mode) 应注册 UIT2")
        }
        for mode in [PageTurnMode.flip, .curl] {
            XCTAssertFalse(MotionEffectCatalog.isRegistered(.uit2EdgeBack, in: mode),
                           "\(mode)（仿真）不应注册 UIT2")
        }
        for id in MotionID.allCases where id != .uit2EdgeBack {
            for mode in PageTurnMode.allCases {
                XCTAssertTrue(MotionEffectCatalog.isRegistered(id, in: mode),
                              "\(id) 在 \(mode.displayName) 下应注册")
            }
        }
        // UIT1 承载「仿真/双页下顶栏返回恒可达」⇒ UIT1 必须**所有模式都注册**
        for mode in PageTurnMode.allCases {
            XCTAssertTrue(MotionEffectCatalog.isRegistered(.uit1ChromeToggle, in: mode),
                          "UIT1 在 \(mode.displayName) 下必须注册（顶栏返回恒可达）")
        }
    }

    // MARK: - EGG5 专项（限流一并停跑）

    /// EGG5 关态「摇动无响应（**限流一并停跑**）」：停跑时**不消耗限流额度**——
    /// 否则用户关掉动效期间会白扣次数，重新打开后第一次摇就被挡掉。
    @MainActor
    func testEGG5RateLimiterStopsWithMotionAndDoesNotConsumeQuota() {
        let limiter = ShakeRateLimiter(limitPerMinute: 3)
        XCTAssertTrue(limiter.isRunning)
        XCTAssertTrue(limiter.allowsTrigger(), "在跑时应放行")
        XCTAssertEqual(limiter.consumedCount, 1)

        // 动效关闭 ⇒ 限流一并停跑
        limiter.setRunning(false)
        XCTAssertFalse(limiter.isRunning)
        XCTAssertFalse(limiter.allowsTrigger(), "停跑时摇动必须无响应")
        XCTAssertEqual(limiter.consumedCount, 0, "停跑不得消耗限流额度")

        // 重新打开 ⇒ 恢复放行
        limiter.setRunning(true)
        XCTAssertTrue(limiter.allowsTrigger())
        XCTAssertEqual(limiter.consumedCount, 1)
    }

    /// EGG5 关态：`perform` **连触发一起短路** ⇒ 面板不出现（dropTrigger）。
    @MainActor
    func testEGG5DropTriggerShortCircuitsWhenOff() {
        let off = MotionCoordinator(isMotionEnabled: false)
        var fired = false
        off.perform(.egg5ShakePanel) { fired = true }
        XCTAssertFalse(fired, "EGG5 关态：摇动无响应、面板不出现")
    }

    /// EGG5 仅在**阅读工具条展开**时生效（书摘卡与「换一个版本」是两条独立路径）。
    @MainActor
    func testEGG5RequiresReadingToolbarExpanded() {
        XCTAssertEqual(MotionEffectCatalog.descriptor(for: .egg5ShakePanel).activation, .readingToolbarExpanded)
        // 其余 12 个 ID 无前置条件
        for id in MotionID.allCases where id != .egg5ShakePanel {
            XCTAssertEqual(MotionEffectCatalog.descriptor(for: id).activation, .anytime,
                           "\(id) 无额外触发前置条件")
        }
    }

    // MARK: - 材质插值守卫

    /// 动效期间**禁止插值材质参数**（tint/blur/refraction）——纪律写进类型：13 条全为 false。
    @MainActor
    func testNoMotionEffectInterpolatesMaterial() {
        for id in MotionID.allCases {
            XCTAssertFalse(MotionEffectCatalog.descriptor(for: id).interpolatesMaterial,
                           "\(id) 不得插值材质参数（材质一变即触发 backdrop 全屏重算）")
        }
    }

    // MARK: - 系统「减弱动态效果」（优先级最高）

    /// 系统「减弱动态效果」：**只去动画、不去功能**——与用户总关的 dropTrigger 短路语义不同。
    @MainActor
    func testSystemReduceMotionRemovesAnimationButKeepsFunction() {
        let coordinator = MotionCoordinator()
        coordinator.systemReduceMotion = true

        for id in MotionID.allCases {
            XCTAssertFalse(coordinator.shouldAnimate(id), "\(id) 减弱动态效果下不应播动画")
            XCTAssertNil(coordinator.animation(for: id), "\(id) 减弱动态效果下应走不播动画路径")
        }
        // 功能不减：keepTrigger 的 ID 触发照常执行
        var fired = false
        coordinator.perform(.t2VersionSwap) { fired = true }
        XCTAssertTrue(fired, "减弱动态效果只去动画，不去功能")
        // dropTrigger 的 ID 在「动效开着」时同样应执行触发（功能不减）
        var firedEgg = false
        coordinator.perform(.egg5ShakePanel) { firedEgg = true }
        XCTAssertTrue(firedEgg, "减弱动态效果下 dropTrigger 的 ID 仍应执行触发")
    }

    /// 13 条实现描述都必须登记**自然触发位置**（DESIGN §4.1 单一来源）——
    /// 供「把动效接到产品界面真实位置」时取用，避免各人各写一份。
    @MainActor
    func testEveryDescriptorRecordsNaturalTriggerPosition() {
        for id in MotionID.allCases {
            let trigger = MotionEffectCatalog.descriptor(for: id).naturalTrigger
            XCTAssertFalse(trigger.isEmpty, "\(id) 必须登记自然触发位置")
        }
    }

    /// 逐 ID 的**曲线与时长**必须登记（DESIGN §4.1 单一来源）——**不共用一个时长**。
    @MainActor
    func testEveryMotionHasRegisteredTiming() {
        for id in MotionID.allCases {
            let timing = MotionEffectCatalog.timing(for: id)
            XCTAssertGreaterThan(timing.duration, 0, "\(id) 必须登记时长")
            XCTAssertGreaterThanOrEqual(timing.damping, 0, "\(id) 阻尼系数须合法")
            XCTAssertGreaterThanOrEqual(timing.stagger, 0, "\(id) 错峰间隔须合法")
        }
        // 关键差异点：DESIGN 逐 ID 时长不同 ⇒ 不得全部共用一个值
        XCTAssertNotEqual(MotionEffectCatalog.timing(for: .t2VersionSwap).duration,
                          MotionEffectCatalog.timing(for: .t5SwitchRipple).duration,
                          "T2（260ms）与 T5（600ms）时长不同，不得共用")
        // 错峰：T6 间隔 25ms、EGG3 墨滴 60ms
        XCTAssertEqual(MotionEffectCatalog.timing(for: .t6InkGrow).stagger, 0.025, accuracy: 0.0001)
        XCTAssertEqual(MotionEffectCatalog.timing(for: .egg3PaperPull).stagger, 0.06, accuracy: 0.0001)
    }

    /// 协调器的标准动画**逐 ID 派生**（不得全部共用一个时长）。
    @MainActor
    func testCoordinatorUsesPerIDTiming() {
        let coordinator = MotionCoordinator()
        XCTAssertNotNil(coordinator.animation(for: .t2VersionSwap))
        XCTAssertNotNil(coordinator.animation(for: .t5SwitchRipple))
        // 时长不同 ⇒ 动画对象不同（SwiftUI Animation 为值类型，可比较）
        XCTAssertNotEqual(coordinator.animation(for: .t2VersionSwap),
                          coordinator.animation(for: .t5SwitchRipple),
                          "不同 ID 应使用各自的曲线与时长")
    }

    /// EGG5 的**年龄态注册条件**：仅 `.adultConfirmed`（DESIGN §4.1）——其余 12 个无年龄限制。
    @MainActor
    func testEGG5RegistersOnlyForAdultConfirmed() {
        XCTAssertEqual(MotionEffectCatalog.descriptor(for: .egg5ShakePanel).ageGate, .adultConfirmedOnly)
        for id in MotionID.allCases where id != .egg5ShakePanel {
            XCTAssertEqual(MotionEffectCatalog.descriptor(for: id).ageGate, .any,
                           "\(id) 无年龄态注册限制")
        }
    }

    // MARK: - 目录完整性（13 条，一个不多一个不少）

    @MainActor
    func testCatalogHasExactlyThirteenDescriptorsCoveringAllIDs() {
        XCTAssertEqual(MotionEffectCatalog.all.count, 13, "动效目录必须恰好 13 条")
        XCTAssertEqual(Set(MotionEffectCatalog.all.map(\.id)), Set(MotionID.allCases),
                       "目录必须覆盖全部 13 个 ID")
        // 13 个开态视觉一一对应（不得两个 ID 共用一个视觉实现）
        XCTAssertEqual(Set(MotionEffectCatalog.all.map(\.visual)).count, 13,
                       "13 个动效的开态视觉应各不相同")
        for id in MotionID.allCases {
            XCTAssertEqual(MotionEffectCatalog.descriptor(for: id).id, id)
        }
    }

    // MARK: - 容器尺寸贯通（缺口 a）

    /// 容器尺寸**只有一个来源**（`ReaderLayout.shared`）：不得引入第二套尺寸常量。
    @MainActor
    func testContainerSizeHasSingleSource() {
        XCTAssertTrue(ReaderLayout.shared === ReaderLayout.shared, "布局来源必须是单例")
        // 种子值取既有常量（不引入第二套尺寸常量）
        XCTAssertEqual(ReaderLayout().containerSize, ReaderEngine.defaultContainerSize,
                       "种子值必须取既有 `ReaderEngine.defaultContainerSize`")
        // 两端共用的签名入口
        let sig = ReaderLayout.shared.currentSignature(typography: .default)
        XCTAssertEqual(sig.digest,
                       TypographySignature(typography: .default,
                                            containerSize: ReaderLayout.shared.containerSize,
                                            screenScale: ReaderLayout.shared.screenScale,
                                            kinsokuVersion: Kinsoku.v1.version).digest,
                       "签名入口必须与当前尺寸/缩放一致")
    }

    /// 容器尺寸贯通 ⇒ 设置页与阅读器两端签名一致 ⇒ **锚点缓存真正互通**（第二端命中、不作废）。
    @MainActor
    func testSettingsAndReaderPaginationShareAnchorCache() {
        let layout = ReaderLayout()   // 本地实例，避免污染全局单例
        layout.update(containerSize: CGSize(width: 393, height: 852), screenScale: 3.0)
        let coordinator = PaginationCoordinator()   // 独立实例便于断言
        let text = sampleChapter()
        let typography = ReaderTypography.default

        // 设置页侧重排
        let settingsSession = ReaderSession(
            engine: ReaderEngine(bookID: "b1", chapterID: 1, chapterText: text,
                                 typography: typography, containerSize: layout.containerSize),
            coordinator: coordinator)
        let settingsOutcome = settingsSession.applyTypography(typography,
                                                             containerSize: layout.containerSize,
                                                             screenScale: layout.screenScale)
        XCTAssertTrue(settingsOutcome.cacheInvalidated, "首次重排应作废缓存并重排")

        // 阅读器侧重排（**同一容器尺寸来源** ⇒ 同一签名 ⇒ 命中缓存）
        let readerSession = ReaderSession(
            engine: ReaderEngine(bookID: "b1", chapterID: 1, chapterText: text,
                                 typography: typography, containerSize: layout.containerSize),
            coordinator: coordinator)
        let readerOutcome = readerSession.applyTypography(typography,
                                                          containerSize: layout.containerSize,
                                                          screenScale: layout.screenScale)
        XCTAssertFalse(readerOutcome.cacheInvalidated,
                       "两端容器尺寸一致 ⇒ 签名一致 ⇒ 应命中缓存（不重复作废、不重复排版）")
        XCTAssertEqual(readerOutcome.status, .unchanged)
        XCTAssertEqual(settingsOutcome.newSignature, readerOutcome.newSignature,
                       "两端签名必须一致")
    }

    // MARK: - 单例由构造保证（缺口 b）

    /// 不传参即得 App 级单例——单例靠**构造**保证，不靠「记得传 `.shared`」。
    @MainActor
    func testSingletonIsGuaranteedByConstruction() {
        let session = ReaderSession(engine: nil)
        XCTAssertTrue(session.coordinator === PaginationCoordinator.shared,
                      "ReaderSession 默认协调器必须是 App 级单例")
        let scheduler = RepaginationScheduler()
        XCTAssertTrue(scheduler.coordinator === PaginationCoordinator.shared,
                      "RepaginationScheduler 默认协调器必须是 App 级单例")
        // 需要隔离时仍可显式传独立实例（单测用）
        XCTAssertFalse(PaginationCoordinator() === PaginationCoordinator.shared,
                       "独立实例必须与单例不是同一对象")
    }
}
