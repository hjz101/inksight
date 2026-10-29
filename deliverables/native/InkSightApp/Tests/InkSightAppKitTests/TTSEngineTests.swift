import XCTest
@testable import InkSightAppKit

/// FR-012 TTS 朗读契约测试。
final class TTSEngineTests: XCTestCase {

    // MARK: - 设置与语速范围

    /// 语速范围 **0.5–2.5**（FR-012 原文）。
    func testRateRangeConstants() {
        XCTAssertEqual(TTSSettings.minRate, 0.5)
        XCTAssertEqual(TTSSettings.maxRate, 2.5)
        XCTAssertEqual(TTSSettings.defaultRate, 1.0)
    }

    /// 越界语速**夹取**到合法区间（不是静默忽略）。
    func testRateClamping() {
        XCTAssertEqual(TTSSettings(rateMultiplier: 0.1).clampedRate, 0.5)
        XCTAssertEqual(TTSSettings(rateMultiplier: 5.0).clampedRate, 2.5)
        XCTAssertEqual(TTSSettings(rateMultiplier: 1.5).clampedRate, 1.5)
    }

    /// 归一化写回（防越界值落盘）。
    @MainActor
    func testNormalizeOnInit() {
        let engine = TTSEngine(settings: TTSSettings(rateMultiplier: 99))
        XCTAssertEqual(engine.settings.rateMultiplier, 2.5, "初始化应归一化越界语速")
    }

    /// 定时关闭档位。
    func testSleepTimerOptions() {
        XCTAssertEqual(TTSSettings.sleepTimerOptions, [15, 30, 60])
    }

    // MARK: - 分段

    /// 分段覆盖全文且 offset 递增（无遗漏、无重叠）。
    func testSegmentationCoversText() {
        let text = String(repeating: "第一章内容。", count: 200)  // 1200 字
        let segs = TTSEngine.segment(text, from: 0)
        XCTAssertFalse(segs.isEmpty)
        // 首段从 0 开始
        XCTAssertEqual(segs[0].offset, 0)
        // offset 严格递增
        for i in 1..<segs.count {
            XCTAssertGreaterThan(segs[i].offset, segs[i-1].offset)
        }
        // 拼接后总长等于原文
        XCTAssertEqual(segs.map(\.text).joined(), text, "分段拼接应还原全文")
    }

    /// 从中间偏移开始分段（续读）。
    func testSegmentationFromOffset() {
        let text = String(repeating: "a", count: 1000)
        let segs = TTSEngine.segment(text, from: 500)
        XCTAssertEqual(segs[0].offset, 500)
        XCTAssertEqual(segs.map(\.text).joined(), String(repeating: "a", count: 500))
    }

    /// 越界偏移返回空（诚实，不崩）。
    func testSegmentationOutOfRange() {
        XCTAssertTrue(TTSEngine.segment("abc", from: 99).isEmpty)
        XCTAssertTrue(TTSEngine.segment("", from: 0).isEmpty)
    }

    // MARK: - 语速映射

    /// 语速倍数 → AVSpeechUtterance rate（系统 0…1）。
    func testAVRateMapping() {
        XCTAssertEqual(TTSEngine.avRate(for: 1.0), 0.5, accuracy: 0.001)
        XCTAssertEqual(TTSEngine.avRate(for: 0.5), 0.25, accuracy: 0.001)
        XCTAssertEqual(TTSEngine.avRate(for: 2.5), 1.0, accuracy: 0.001, "2.5 倍应封顶到 1.0")
        // 恒在系统合法区间
        for m in stride(from: 0.1, through: 5.0, by: 0.1) {
            let r = TTSEngine.avRate(for: m)
            XCTAssertTrue(r >= 0 && r <= 1, "映射结果须在 0…1：\(m) -> \(r)")
        }
    }

    // MARK: - 状态机

    /// 初始 idle。
    @MainActor
    func testInitialState() {
        let engine = TTSEngine()
        XCTAssertEqual(engine.state, .idle)
        XCTAssertFalse(engine.state.isActive)
    }

    /// start 后进入 speaking；stop 回到 idle。
    @MainActor
    func testStartAndStop() {
        let engine = TTSEngine()
        engine.start(text: String(repeating: "朗读内容。", count: 50))
        XCTAssertEqual(engine.state, .speaking)
        XCTAssertEqual(engine.currentCharOffset, 0, "从头开始 offset 为 0")

        engine.stop()
        XCTAssertEqual(engine.state, .idle)
    }

    /// 空文本不进入 speaking（诚实空态）。
    @MainActor
    func testStartWithEmptyTextStaysIdle() {
        let engine = TTSEngine()
        engine.start(text: "")
        XCTAssertEqual(engine.state, .idle, "无内容不应假装在朗读")
    }

    /// pause / resume。
    @MainActor
    func testPauseResume() {
        let engine = TTSEngine()
        engine.start(text: String(repeating: "内容。", count: 100))
        engine.pause()
        XCTAssertEqual(engine.state, .paused)
        engine.resume()
        XCTAssertEqual(engine.state, .speaking)
    }

    /// 未在朗读时 pause 无效（不崩）。
    @MainActor
    func testPauseWhenIdleIsNoop() {
        let engine = TTSEngine()
        engine.pause()
        XCTAssertEqual(engine.state, .idle)
    }

    /// 续读：从指定偏移开始。
    @MainActor
    func testStartFromOffset() {
        let engine = TTSEngine()
        engine.start(text: String(repeating: "x", count: 500), startingOffset: 200)
        XCTAssertEqual(engine.currentCharOffset, 200, "续读应从指定偏移开始")
    }

    /// 更新语速即时生效且夹取。
    @MainActor
    func testUpdateRateClamps() {
        let engine = TTSEngine()
        engine.updateRate(1.75)
        XCTAssertEqual(engine.settings.rateMultiplier, 1.75)
        engine.updateRate(99)
        XCTAssertEqual(engine.settings.rateMultiplier, 2.5)
    }
}

/// D-93 缺陷修复验证：段推进由 delegate 驱动，不再"排入即自增"。
@MainActor
final class TTSDelegateAdvanceTests: XCTestCase {

    /// **关键**：`start` 后只朗读第一段，`segmentIndex` 不应被提前推进。
    ///
    /// 修复前：`speakCurrentSegment` 内部 `segmentIndex += 1` → 一次 start 就把
    /// 全部段排入队列，offset 推进与朗读脱节。
    func testStartDoesNotAdvanceAhead() {
        let engine = TTSEngine()
        // 1200 字 → 3 段（每段 400）
        engine.start(text: String(repeating: "字", count: 1200))
        XCTAssertEqual(engine.state, .speaking)
        // 首段 offset 为 0，且**不应**已经前进到第 2 段
        XCTAssertEqual(engine.currentCharOffset, 0,
                       "start 后应停在首段，不得提前推进（D-93 缺陷）")
    }

    /// 段读完推进到下一段 offset。
    func testAdvanceMovesToNextSegment() {
        let engine = TTSEngine()
        engine.start(text: String(repeating: "字", count: 1200))
        engine.advanceAfterSegmentFinished()
        XCTAssertEqual(engine.currentCharOffset, 400, "读完首段应推进到第二段（400）")
    }

    /// 全部读完 → 回到 idle 并回调 `onFinishedChapter`。
    func testFinishAllSegmentsStopsAndNotifies() {
        let engine = TTSEngine()
        var finished = false
        engine.onFinishedChapter = { finished = true }
        engine.start(text: String(repeating: "字", count: 1200))  // 3 段
        engine.advanceAfterSegmentFinished()  // → 段2
        engine.advanceAfterSegmentFinished()  // → 段3
        engine.advanceAfterSegmentFinished()  // → 读完
        XCTAssertEqual(engine.state, .idle, "全章读完应回到 idle")
        XCTAssertTrue(finished, "应回调 onFinishedChapter")
    }

    /// idle 时推进无效（不崩、不误触发）。
    func testAdvanceWhenIdleIsNoop() {
        let engine = TTSEngine()
        engine.advanceAfterSegmentFinished()
        XCTAssertEqual(engine.state, .idle)
    }
}
