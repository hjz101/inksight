import XCTest
@testable import InkSightAppKit
import InkSightCore
import Foundation

/// 计数盒（引用类型，便于在转义闭包中安全累加计数）。
private final class CounterBox { var count = 0 }

/// 常驻计数盒：统计「正文被物化但尚未释放」的章数，用于验证**常驻正文 ≤1 章**（NFR-09 ②）。
private final class ResidencyBox {
    var live = 0        // 当前未释放的正文章数
    var maxLive = 0     // 观测到的峰值
    var total = 0       // 累计物化次数
}

/// 开发包 #8 契约测试：重分页回接真实阅读链路 ＋ 后台调度真实驱动。
///
/// 覆盖：重排后落点保持（≤1 屏）／持久化模型仍无 pageIndex／后台调度可取消／
/// 常驻正文 ≤1 章／真实书接线（未预取全书）／诚实空态。
final class RepaginationIntegrationTests: XCTestCase {

    private let containerSize = CGSize(width: 360, height: 720)
    private let screenScale: Double = 1.0

    /// 确定性示例章节（多段，足以分页成多页）。
    private func sampleChapter() -> String {
        let para = "墨见读书专注于本地阅读，支持自定义字号行高与边距，并严守定位铁律只以字符偏移加段落指纹恢复进度。"
        return (0..<16).map { _ in para }.joined(separator: "\n")
    }

    /// 换字号（触发签名变化）。
    private func largerTypography() -> ReaderTypography {
        var t = ReaderTypography.default
        t.fontSize = 22
        return t
    }

    // MARK: - 重排后落点保持

    /// 重排后落点必须落在「**同一 `charOffset` 所属的新页**」上，误差 ≤1 屏；
    /// 落点 `charOffset` 本身**不变**（定位铁律：靠 charOffset 重新二分，不靠 pageIndex）。
    func testRepaginationKeepsLandingOnSameCharOffset() throws {
        let engine = ReaderEngine(bookID: "b1", chapterID: 1, chapterText: sampleChapter())
        // 显式独立协调器：NFR-13 默认构造即 .shared 单例，集成测试必须隔离，避免跨测试签名污染
        let session = ReaderSession(engine: engine, coordinator: PaginationCoordinator())

        // 落点取中间某页的页首（首字符太弱，取中间页才能真正检验「跨分页重定位」）
        let targetIndex = max(1, engine.pages.count / 2)
        let targetOffset = engine.pages[targetIndex].anchor.charOffset
        engine.recordProgress(at: targetOffset)
        XCTAssertEqual(session.landingCharOffset, targetOffset, "落点应取进度里的 charOffset")

        let outcome = session.applyTypography(largerTypography(),
                                             containerSize: containerSize,
                                             screenScale: screenScale)

        XCTAssertEqual(outcome.status, .ok, "签名变化应触发重排")
        XCTAssertTrue(outcome.cacheInvalidated)
        XCTAssertEqual(outcome.landingCharOffset, targetOffset, "落点 charOffset 重排前后必须不变")

        let newEngine = try XCTUnwrap(session.engine)
        // 新页索引由 charOffset 经**新锚点**二分得到（不是旧页码）
        XCTAssertEqual(outcome.landingPageIndex, newEngine.resolvePageIndex(for: targetOffset))
        // 落点确实属该新页（分页连续全覆盖 → 二分必然命中唯一页）
        let page = try XCTUnwrap(newEngine.page(at: outcome.landingPageIndex))
        XCTAssertTrue(targetOffset >= page.anchor.charOffset
                      && targetOffset < page.anchor.charOffset + page.anchor.charLength,
                      "目标 charOffset 必须落在重排后的该新页内")
        // 误差 ≤1 屏（＝不超过该页覆盖的字符数）
        XCTAssertLessThanOrEqual(outcome.landingErrorChars, outcome.landingPageLength,
                                 "落点误差应 ≤1 屏")
    }

    /// 持久化模型仍只 `charOffset + fingerprint`——**无 pageIndex**（定位铁律不得回退）。
    func testReadingProgressModelStillHasNoPageIndex() throws {
        let progress = ReadingProgress(bookID: "b1", chapterID: 1, charOffset: 42, fingerprint: 0xABCD)
        let data = try JSONEncoder().encode(progress)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(obj.keys), ["bookID", "chapterID", "charOffset", "fingerprint"],
                       "进度模型键集必须仍是这 4 个")
        XCTAssertFalse(obj.keys.contains("pageIndex"), "持久化模型绝不可出现 pageIndex")
    }

    /// 重排后进度仓库里存的仍是 `charOffset + fingerprint`（重排不把页码写进进度）。
    func testProgressStoreAfterRepaginationHasNoPageIndex() throws {
        let engine = ReaderEngine(bookID: "b1", chapterID: 1, chapterText: sampleChapter())
        let session = ReaderSession(engine: engine, coordinator: PaginationCoordinator())
        let targetOffset = engine.pages[max(1, engine.pages.count / 2)].anchor.charOffset
        engine.recordProgress(at: targetOffset)

        _ = session.applyTypography(largerTypography(), containerSize: containerSize, screenScale: screenScale)

        let newEngine = try XCTUnwrap(session.engine)
        let stored = try XCTUnwrap(newEngine.currentProgress())
        XCTAssertEqual(stored.charOffset, targetOffset, "重排后进度仍是同一 charOffset")
        XCTAssertNotEqual(stored.fingerprint, 0, "指纹应随新锚点更新")
    }

    // MARK: - 后台调度：可取消 ＋ 每批 1 章

    /// 后台调度可取消：取消后处理章数**停止增长**，且不再取正文。
    /// 用手动 `processNextBatch` 驱动（与后台循环**同一条处理路径**），不依赖真实时钟。
    func testBackgroundSchedulerStopsAfterCancel() throws {
        let coordinator = PaginationCoordinator()
        let scheduler = RepaginationScheduler(coordinator: coordinator)
        let residency = ResidencyBox()
        let text = sampleChapter()

        let chapters: [(id: Int, textProvider: () -> String?)] = (0..<5).map { i in
            (id: i, textProvider: { () -> String? in
                residency.live += 1
                residency.total += 1
                residency.maxLive = max(residency.maxLive, residency.live)
                return text
            })
        }
        // 入队：**只登记闭包，不读任何正文**
        coordinator.enqueueBackgroundLazy(chapters)
        XCTAssertEqual(residency.total, 0, "入队时不得取正文（未预取全书）")

        // 处理 2 批（＝2 章）
        for _ in 0..<2 {
            XCTAssertTrue(scheduler.processNextBatch(typography: .default,
                                                     containerSize: containerSize,
                                                     screenScale: screenScale))
            residency.live -= 1   // 该批处理完 → 正文释放
        }
        XCTAssertEqual(scheduler.processedChapterCount, 2)
        XCTAssertEqual(residency.total, 2, "处理 2 章只取 2 次正文")
        XCTAssertEqual(residency.maxLive, 1, "常驻正文 ≤1 章")

        // 取消 → 不再处理
        scheduler.cancel()
        XCTAssertTrue(scheduler.isCancelled)
        XCTAssertFalse(scheduler.processNextBatch(typography: .default,
                                                  containerSize: containerSize,
                                                  screenScale: screenScale),
                       "取消后不得再处理")
        XCTAssertEqual(scheduler.processedChapterCount, 2, "取消后处理章数不再增长")
        XCTAssertEqual(residency.total, 2, "取消后不再取正文")
    }

    /// 真实后台循环（`Task.detached`）路径：取消后计数停止增长。
    func testBackgroundSchedulerRealLoopStopsAfterCancel() async throws {
        let coordinator = PaginationCoordinator()
        let scheduler = RepaginationScheduler(coordinator: coordinator, batchDelay: .milliseconds(60))
        let residency = ResidencyBox()
        let text = sampleChapter()
        let chapters: [(id: Int, textProvider: () -> String?)] = (0..<5).map { i in
            (id: i, textProvider: { () -> String? in
                residency.live += 1
                residency.total += 1
                residency.maxLive = max(residency.maxLive, residency.live)
                return text
            })
        }

        let total = scheduler.start(chapters: chapters, typography: .default,
                                    containerSize: containerSize, screenScale: screenScale)
        XCTAssertEqual(total, 5)
        XCTAssertEqual(scheduler.totalChapterCount, 5)
        XCTAssertEqual(residency.total, 0, "入队时不取正文")

        // 等到真实推进（后台线程真的在跑）
        let progressed = await waitUntil { scheduler.processedChapterCount >= 2 }
        XCTAssertTrue(progressed, "后台调度应真实推进")

        // 取消 → 让在处理的那一章跑完 → 再取快照
        scheduler.cancel()
        try? await Task.sleep(for: .milliseconds(250))
        let countAfterCancel = scheduler.processedChapterCount
        let bodyAfterCancel = residency.total

        // 之后不再增长
        try? await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(scheduler.processedChapterCount, countAfterCancel, "取消后处理章数不再增长")
        XCTAssertEqual(residency.total, bodyAfterCancel, "取消后不再取正文")
        XCTAssertTrue(scheduler.isCancelled)
    }

    // MARK: - 真实书接线

    /// 真实导入的书 → `BookShelfStore.chapterText(for:)` 作 `textProvider` →
    /// 产出锚点，且**未预取全书**（只处理 1 章 ⇒ 只取 1 次正文，其余章正文从未被读）。
    func testRealBookFeedsTextProviderWithoutPrefetchingWholeBook() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-b8-\(UUID().uuidString).txt")
        let content = (0..<4).map { i in
            "第\(i)章\n" + String(repeating: "这是第\(i)章的正文内容，用于验证真实书接线与按需切片读取。", count: 8)
        }.joined(separator: "\n\n")
        try content.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let shelf = BookShelfStore()
        let item = try shelf.importLocalBook(bookID: "local-b8", title: "测试书", fileURL: tmp)
        XCTAssertGreaterThan(item.chapters.count, 1, "应分出多章")

        let coordinator = PaginationCoordinator()
        let scheduler = RepaginationScheduler(coordinator: coordinator)
        let residency = ResidencyBox()
        let chapters: [(id: Int, textProvider: () -> String?)] = item.chapters.indices.map { index in
            (id: index, textProvider: { () -> String? in
                residency.live += 1
                residency.total += 1
                residency.maxLive = max(residency.maxLive, residency.live)
                return shelf.chapterText(for: item, chapterIndex: index)
            })
        }
        coordinator.enqueueBackgroundLazy(chapters)
        XCTAssertEqual(residency.total, 0, "入队不取正文")

        XCTAssertTrue(scheduler.processNextBatch(typography: .default,
                                                 containerSize: containerSize,
                                                 screenScale: screenScale))
        residency.live -= 1

        XCTAssertEqual(residency.total, 1, "只处理 1 章 ⇒ 只取 1 次正文（未预取全书）")
        XCTAssertEqual(residency.maxLive, 1, "常驻正文 ≤1 章")

        // 锚点确实产出
        let sig = TypographySignature(typography: .default, containerSize: containerSize,
                                       screenScale: screenScale, kinsokuVersion: Kinsoku.v1.version)
        let anchors = coordinator.pageAnchorCache.anchors(for: 0, signatureHash: sig.digest)
        XCTAssertNotNil(anchors, "后台章重分页后应落库锚点")
        XCTAssertFalse(anchors?.isEmpty ?? true, "锚点不应为空")
    }

    // MARK: - 诚实空态

    /// 无引擎（无当前书）→ 诚实空态 `.noContent`：**不伪装成功**、不触发缓存作废。
    func testApplyTypographyWithNoEngineReturnsHonestEmptyOutcome() {
        let session = ReaderSession(engine: nil, coordinator: PaginationCoordinator())
        let outcome = session.applyTypography(.default, containerSize: containerSize, screenScale: screenScale)

        XCTAssertEqual(outcome.status, .noContent)
        XCTAssertFalse(outcome.cacheInvalidated, "无正文不得触发缓存作废")
        XCTAssertEqual(outcome.currentChapterRetimeMs, 0)
        XCTAssertEqual(outcome.pageCountAfter, 0, "无正文不得产出页数")
        XCTAssertTrue(outcome.message.contains("无可重排内容"), "空态须如实说明：\(outcome.message)")
        XCTAssertNil(session.engine, "无正文不得产生引擎")
    }

    /// 有引擎但正文为空 → 同样是诚实空态。
    func testApplyTypographyWithEmptyChapterTextReturnsHonestEmptyOutcome() {
        let engine = ReaderEngine(bookID: "b1", chapterID: 1, chapterText: "")
        let session = ReaderSession(engine: engine, coordinator: PaginationCoordinator())
        let outcome = session.applyTypography(.default, containerSize: containerSize, screenScale: screenScale)

        XCTAssertEqual(outcome.status, .noContent)
        XCTAssertTrue(outcome.message.contains("无可重排内容"))
    }

    /// 书架为空 → `currentItem` 为 nil（调用方据此走诚实空态，不伪造书目）。
    func testEmptyShelfHasNoCurrentItem() {
        let shelf = BookShelfStore()
        XCTAssertNil(shelf.currentItem, "空书架不得有当前书")
    }

    // MARK: - 协调器单例（缓存共享）

    /// App 级单例协调器：设置页与阅读器必须共用同一实例——
    /// 否则 `PageAnchorCache` / `CTFrameCache` 各挂一套，同一本书排两遍、
    /// 缓存互不命中，NFR-03 内存预算按实例翻倍。
    func testPaginationCoordinatorHasAppLevelSharedInstance() {
        XCTAssertTrue(PaginationCoordinator.shared === PaginationCoordinator.shared,
                      "单例必须是同一对象")
        XCTAssertFalse(PaginationCoordinator.shared === PaginationCoordinator(),
                       "独立实例与单例不得是同一对象（测试用独立实例，避免跨用例污染）")
        // 单例持有的是冻结契约规定的两个缓存，容量不得漂移
        XCTAssertEqual(PaginationCoordinator.shared.pageAnchorCache.anchors(for: 0, signatureHash: "none"), nil)
    }

    // MARK: - 工具

    /// 轮询等待条件成立（带超时）。
    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 5.0) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    // MARK: - 会话释放（合规四禁令第 4 条：切书/会话结束即释放）

    /// **释放钩子必须真的清缓存**。
    ///
    /// 历史缺口：`CTFrame` 四禁令写着「切书或会话结束即释放」，但 `invalidateAll()`
    /// 此前**只在签名变化时**被调用——切书、退出阅读器都没有调用方，
    /// 即这条禁令在代码里从未被执行过。本测试锁住新增的显式释放路径。
    func testEndSessionActuallyClearsCaches() {
        let coordinator = PaginationCoordinator()
        let engine = ReaderEngine(bookID: "book-a", chapterID: 1,
                                  chapterText: sampleChapter(), typography: .default)
        let session = ReaderSession(engine: engine, coordinator: coordinator)

        // 先真正写入锚点缓存（通过 apply 走一遍重排链路）
        let outcome = session.applyTypography(.default)
        XCTAssertEqual(outcome.status, .ok)
        let sig = outcome.newSignature
        XCTAssertNotNil(coordinator.pageAnchorCache.anchors(for: 1, signatureHash: sig),
                        "前置：apply 后锚点应已缓存")

        // 会话结束 → 缓存必须被清空
        session.endSession()
        XCTAssertNil(coordinator.pageAnchorCache.anchors(for: 1, signatureHash: sig),
                     "endSession 后锚点缓存必须清空（世代号已 +1，旧条目失配）")
    }

    /// **切书（bookID 变化）触发释放；同书换章不触发**。
    func testAdoptNewBookReleasesOldSessionButSameBookDoesNot() {
        let coordinator = PaginationCoordinator()
        let bookA = ReaderEngine(bookID: "book-a", chapterID: 1, chapterText: sampleChapter(), typography: .default)
        let session = ReaderSession(engine: bookA, coordinator: coordinator)
        let outcome = session.applyTypography(.default)
        let sig = outcome.newSignature
        XCTAssertNotNil(coordinator.pageAnchorCache.anchors(for: 1, signatureHash: sig))

        // 同书换章：不释放（否则翻页会反复重排）
        let sameBookCh2 = ReaderEngine(bookID: "book-a", chapterID: 2, chapterText: sampleChapter(), typography: .default)
        session.adopt(sameBookCh2)
        XCTAssertNotNil(coordinator.pageAnchorCache.anchors(for: 1, signatureHash: sig),
                        "同书换章不得释放缓存")

        // 换书：必须释放
        let bookB = ReaderEngine(bookID: "book-b", chapterID: 1, chapterText: sampleChapter(), typography: .default)
        session.adopt(bookB)
        XCTAssertNil(coordinator.pageAnchorCache.anchors(for: 1, signatureHash: sig),
                     "换书必须释放旧书缓存（切书即释放）")
    }

    /// 释放后后台队列也必须清空——旧书的待重排章不得在新会话继续跑。
    func testReleaseSessionClearsBackgroundQueue() {
        let coordinator = PaginationCoordinator()
        _ = coordinator.apply(.default, chapterText: sampleChapter(), chapterID: 1,
                              containerSize: containerSize, screenScale: screenScale)
        let pending = coordinator.enqueueBackgroundLazy([
            (id: 2, textProvider: { self.sampleChapter() }),
            (id: 3, textProvider: { self.sampleChapter() }),
        ])
        XCTAssertEqual(pending, 2)

        coordinator.releaseSession()
        // 队列已清 → 下一次处理应返回 nil
        XCTAssertNil(coordinator.processOneBackgroundChapter(typography: .default,
                                                            containerSize: containerSize,
                                                            screenScale: screenScale),
                     "释放后后台队列必须为空，不得继续处理旧书的章")
    }
}
