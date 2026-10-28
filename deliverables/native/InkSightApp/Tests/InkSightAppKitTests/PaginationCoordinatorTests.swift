import XCTest
import InkSightAppKit
import InkSightCore

/// 计数盒（引用类型，便于在转义闭包中安全累加计数）。
private final class CounterBox { var count = 0 }

/// 开发包 #6 契约测试：TypographySignature 缓存作废机制链路。
///
/// 三契约：
/// (a) 签名变化 → O(1) 全作废（旧签名锚点失效、新签名锚点生效）；
/// (b) 重分页 anchor 连续全覆盖（偏移首尾相接、总长守恒）；
/// (c) 旧签名复用落空触发重算（同签名再次 apply 命中缓存、不重排、retime=0）。
final class PaginationCoordinatorTests: XCTestCase {

    /// 确定性示例章节（多段，足以分页成多页以验证连续全覆盖）。
    private func sampleChapter() -> String {
        let para = "墨见读书专注于本地阅读，支持自定义字号行高与边距，并严守定位铁律只以字符偏移加段落指纹恢复进度。"
        return (0..<16).map { _ in para }.joined(separator: "\n")
    }

    private let containerSize = CGSize(width: 360, height: 720)
    private let screenScale: Double = 1.0

    private func sig(_ t: ReaderTypography) -> TypographySignature {
        TypographySignature(typography: t, containerSize: containerSize,
                            screenScale: screenScale, kinsokuVersion: Kinsoku.v1.version)
    }

    /// 签名 A：默认排版。
    private func a() -> ReaderTypography { .default }
    /// 签名 B：改字号触发签名变化。
    private func b() -> ReaderTypography {
        var t = ReaderTypography.default
        t.fontSize = 22
        return t
    }

    // MARK: - (a) 签名变化 → O(1) 全作废

    func testSignatureChangeInvalidatesCacheO1() throws {
        let coordinator = PaginationCoordinator()
        let sigA = sig(a())
        let sigB = sig(b())

        let r1 = coordinator.apply(a(), chapterText: sampleChapter(), chapterID: 1,
                                   containerSize: containerSize, screenScale: screenScale)
        XCTAssertTrue(r1.cacheInvalidated)
        XCTAssertNil(r1.oldSignature)
        XCTAssertEqual(r1.newSignature, sigA.digest)
        // 旧签名锚点已落库
        XCTAssertNotNil(coordinator.pageAnchorCache.anchors(for: 1, signatureHash: sigA.digest))

        let r2 = coordinator.apply(b(), chapterText: sampleChapter(), chapterID: 1,
                                   containerSize: containerSize, screenScale: screenScale)
        XCTAssertTrue(r2.cacheInvalidated)
        XCTAssertEqual(r2.oldSignature, sigA.digest)
        XCTAssertEqual(r2.newSignature, sigB.digest)
        // O(1) 作废：旧签名锚点已失效（读不到），新签名锚点生效
        XCTAssertNil(coordinator.pageAnchorCache.anchors(for: 1, signatureHash: sigA.digest),
                     "旧签名锚点应在 invalidateAll 后失效")
        XCTAssertNotNil(coordinator.pageAnchorCache.anchors(for: 1, signatureHash: sigB.digest),
                        "新签名锚点应已落库")
    }

    func testWouldInvalidatePureFunction() {
        let coordinator = PaginationCoordinator()
        let sigA = sig(a())
        let sigB = sig(b())
        // 首次：currentSignature 为 nil → 任何新签名都触发作废
        XCTAssertTrue(coordinator.wouldInvalidate(sigA))
        XCTAssertTrue(coordinator.wouldInvalidate(sigB))

        _ = coordinator.apply(a(), chapterText: sampleChapter(), chapterID: 1,
                              containerSize: containerSize, screenScale: screenScale)
        // 当前签名为 A：复用 A 不触发，切换 B 触发
        XCTAssertFalse(coordinator.wouldInvalidate(sigA))
        XCTAssertTrue(coordinator.wouldInvalidate(sigB))
    }

    // MARK: - (b) 重分页 anchor 连续全覆盖

    func testRePaginationAnchorsAreContinuousFullCoverage() throws {
        let coordinator = PaginationCoordinator()
        let chapter = sampleChapter()
        let report = coordinator.apply(a(), chapterText: chapter, chapterID: 1,
                                      containerSize: containerSize, screenScale: screenScale)
        XCTAssertTrue(report.cacheInvalidated)

        let anchors = try XCTUnwrap(coordinator.pageAnchorCache.anchors(for: 1, signatureHash: report.newSignature))
        XCTAssertGreaterThan(anchors.count, 1, "应分页成多页")

        let totalLength = (chapter as NSString).length
        // 连续：第 i+1 页起点 == 第 i 页起点 + 长度
        for i in 0..<(anchors.count - 1) {
            XCTAssertEqual(anchors[i + 1].charOffset, anchors[i].charOffset + anchors[i].charLength,
                          "相邻页锚点必须首尾相接（连续全覆盖）")
        }
        // 末页覆盖到章节结尾
        let last = anchors.last!
        XCTAssertEqual(last.charOffset + last.charLength, totalLength, "末页必须覆盖到章节结尾")
        // 总长守恒
        let sum = anchors.reduce(0) { $0 + $1.charLength }
        XCTAssertEqual(sum, totalLength, "所有页 charLength 之和必须等于章节总长度")
    }

    // MARK: - (c) 旧签名复用落空触发重算

    func testReusingOldSignatureSkipsRecompute() throws {
        let coordinator = PaginationCoordinator()
        let chapter = sampleChapter()
        let r1 = coordinator.apply(a(), chapterText: chapter, chapterID: 1,
                                   containerSize: containerSize, screenScale: screenScale)
        XCTAssertTrue(r1.cacheInvalidated)
        XCTAssertNil(r1.oldSignature)
        let sigADigest = r1.newSignature

        let r2 = coordinator.apply(a(), chapterText: chapter, chapterID: 1,
                                   containerSize: containerSize, screenScale: screenScale)
        XCTAssertFalse(r2.cacheInvalidated, "相同签名再次 apply 应命中缓存、不触发作废")
        XCTAssertEqual(r2.oldSignature, sigADigest)
        XCTAssertEqual(r2.newSignature, sigADigest)
        XCTAssertEqual(r2.currentChapterRetimeMs, 0, "命中缓存不应有重排耗时")

        // 旧签名锚点仍在（未被作废）
        XCTAssertNotNil(coordinator.pageAnchorCache.anchors(for: 1, signatureHash: sigADigest))
    }

    // MARK: - 后台分批重分页（机制链路第 5 步）

    func testBackgroundEnqueueAndProcess() throws {
        let coordinator = PaginationCoordinator()
        // 先 apply 一个签名，使后台章按同签名落库
        _ = coordinator.apply(a(), chapterText: sampleChapter(), chapterID: 1,
                              containerSize: containerSize, screenScale: screenScale)

        let chapters = [
            (id: 2, text: sampleChapter()),
            (id: 3, text: sampleChapter()),
            (id: 4, text: sampleChapter()),
        ]
        let pending = coordinator.enqueueBackground(chapters)
        XCTAssertEqual(pending, 3)

        let sigA = sig(a())
        var processedIDs: [Int] = []
        while let r = coordinator.processOneBackgroundChapter(typography: a(),
                                                             containerSize: containerSize,
                                                             screenScale: screenScale) {
            processedIDs.append(r.id)
            XCTAssertNotNil(coordinator.pageAnchorCache.anchors(for: r.id, signatureHash: sigA.digest),
                            "后台章重分页后应落库锚点")
        }
        XCTAssertEqual(processedIDs.sorted(), [2, 3, 4])
        XCTAssertEqual(coordinator.enqueueBackground([]), 0, "队列清空后应为 0")
    }

    // MARK: - 正文按需取用（NFR-08 / NFR-03 合规由构造保证）

    /// 生产路径：入队**不读正文**，处理时才读——保证「任意时刻常驻正文 ≤1 章」，
    /// 不会把「遍历全书生成 anchor」搬进内存（NFR-08）。
    func testLazyEnqueueDoesNotMaterializeBodyTextUntilProcessed() throws {
        let coordinator = PaginationCoordinator()
        _ = coordinator.apply(a(), chapterText: sampleChapter(), chapterID: 1,
                              containerSize: containerSize, screenScale: screenScale)

        let box = CounterBox()
        let payload = sampleChapter()
        let pending = coordinator.enqueueBackgroundLazy([
            (id: 7, textProvider: { () -> String? in
                box.count += 1
                return payload
            }),
            (id: 8, textProvider: { () -> String? in
                box.count += 1
                return payload
            }),
        ])
        XCTAssertEqual(pending, 2)
        XCTAssertEqual(box.count, 0, "入队时不得读取正文（NFR-08：正文不常驻内存）")

        let sigA = sig(a())
        let first = coordinator.processOneBackgroundChapter(typography: a(),
                                                            containerSize: containerSize,
                                                            screenScale: screenScale)
        XCTAssertEqual(first?.id, 7)
        XCTAssertEqual(box.count, 1, "处理一章只读一章正文")
        XCTAssertNotNil(coordinator.pageAnchorCache.anchors(for: 7, signatureHash: sigA.digest),
                        "后台章重分页后应落库锚点")

        let second = coordinator.processOneBackgroundChapter(typography: a(),
                                                             containerSize: containerSize,
                                                             screenScale: screenScale)
        XCTAssertEqual(second?.id, 8)
        XCTAssertEqual(box.count, 2, "仍是逐章按需读取")
    }

    /// 取不到正文的章应被跳过并继续下一章（源文件被移除等）。
    func testBackgroundSkipsChapterWithUnavailableBody() throws {
        let coordinator = PaginationCoordinator()
        _ = coordinator.apply(a(), chapterText: sampleChapter(), chapterID: 1,
                              containerSize: containerSize, screenScale: screenScale)
        _ = coordinator.enqueueBackgroundLazy([
            (id: 9, textProvider: { nil }),
            (id: 10, textProvider: { self.sampleChapter() }),
        ])
        let r = coordinator.processOneBackgroundChapter(typography: a(),
                                                        containerSize: containerSize,
                                                        screenScale: screenScale)
        XCTAssertEqual(r?.id, 10, "取不到正文的章应被跳过，继续处理下一章")
    }

    /// 当前章同步重排耗时观测（FR-031「当前章同步重排（15–30ms）」的本机量级）。
    /// 用真实 Demo 章节（《红楼梦》第一回，~2 千字）测量；断言取宽松上限以避免 CI 抖动误报，
    /// 真机量级待 POC（两类证据不混装）。
    func testCurrentChapterSyncRetimeIsMeasuredAndBounded() throws {
        let coordinator = PaginationCoordinator()
        let report = coordinator.apply(a(), chapterText: SampleChapter.text, chapterID: SampleChapter.chapterID,
                                       containerSize: containerSize, screenScale: screenScale)
        XCTAssertTrue(report.cacheInvalidated)
        XCTAssertGreaterThan(report.currentChapterRetimeMs, 0, "重排耗时应被真实计量")
        XCTAssertLessThan(report.currentChapterRetimeMs, 1000, "当前章同步重排不应超过 1s（本机宽松上限）")
        print("[REPAGINATE] realChapterRetimeMS=\(report.currentChapterRetimeMs) pages=\(coordinator.pageAnchorCache.anchors(for: SampleChapter.chapterID, signatureHash: report.newSignature)?.count ?? -1)")
    }
}
