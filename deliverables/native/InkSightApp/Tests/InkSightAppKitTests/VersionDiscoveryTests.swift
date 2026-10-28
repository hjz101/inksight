import XCTest
@testable import InkSightAppKit
import InkSightCore

/// FR-018 多副本发现与版本标签持久化测试。
final class VersionDiscoveryTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-vd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func item(_ id: String, title: String, chapters: Int = 3) -> BookShelfItem {
        BookShelfItem(bookID: id, title: title, source: .localImport,
                      importDate: Date(timeIntervalSince1970: 0),
                      chapterCount: chapters,
                      fileURL: URL(fileURLWithPath: "/tmp/\(id).txt"),
                      chapters: (0..<chapters).map {
                          ChapterAnchor(index: $0, title: "第\($0)章", byteOffset: $0 * 100, byteLength: 100)
                      })
    }

    /// 同名副本被发现，且首尾指纹全中 → 匹配度高。
    func testDiscoverSameTitleCopiesWithExactFingerprint() {
        let current = item("a", title: "红楼梦")
        let same = item("b", title: "红楼梦")
        let other = item("c", title: "西游记")

        let results = VersionDiscovery.candidates(
            current: current, shelf: [current, same, other],
            headTail: { _ in (head: "开头相同", tail: "结尾相同") }
        )
        XCTAssertEqual(results.count, 1, "只应发现同名副本（排除自身与不同名）")
        XCTAssertEqual(results.first?.id, "b")
        XCTAssertGreaterThan(results.first?.matchScore ?? 0, 0.9, "首尾全中应高匹配")
    }

    /// 首尾都不匹配 → 匹配度低（但仍作为候选展示，由 UI 明示近似）。
    func testLowScoreWhenFingerprintDiffers() {
        let current = item("a", title: "红楼梦")
        let other = item("b", title: "红楼梦")
        let results = VersionDiscovery.candidates(
            current: current, shelf: [current, other],
            headTail: { item in
                item.bookID == "a" ? (head: "原文开头", tail: "原文结尾")
                                   : (head: "改版开头", tail: "改版结尾")
            }
        )
        XCTAssertEqual(results.count, 1)
        XCTAssertLessThan(results.first?.matchScore ?? 1, 0.5, "首尾不匹配应低分")
    }

    /// 书名归一后比较（空格/标点差异不影响）。
    func testTitleNormalization() {
        let current = item("a", title: "红楼梦")
        let spaced = item("b", title: "红 楼 梦")
        let results = VersionDiscovery.candidates(
            current: current, shelf: [current, spaced],
            headTail: { _ in (head: "x", tail: "y") }
        )
        XCTAssertEqual(results.first?.id, "b", "空格差异不应影响同名判定")
    }

    /// 结果按匹配度降序（FR-018）。
    func testResultsRankedDescending() {
        let current = item("a", title: "红楼梦")
        let high = item("h", title: "红楼梦")
        let low = item("l", title: "红楼梦")
        let results = VersionDiscovery.candidates(
            current: current, shelf: [current, low, high],
            headTail: { item in
                switch item.bookID {
                case "a":  return (head: "原文", tail: "原文尾")
                case "h":  return (head: "原文", tail: "原文尾")
                default:   return (head: "别的", tail: "别的尾")
                }
            }
        )
        XCTAssertEqual(results.map(\.id), ["h", "l"], "应按匹配度降序")
    }

    /// 当前书无 fileURL 时不崩（用章节数估算大小）。
    func testNoFileURLDoesNotCrash() {
        let current = BookShelfItem(bookID: "a", title: "书", source: .localImport,
                                    importDate: Date(), chapterCount: 2, chapters: [])
        let results = VersionDiscovery.candidates(
            current: current, shelf: [current], headTail: { _ in (head: "h", tail: "t") }
        )
        XCTAssertTrue(results.isEmpty, "只有自身时无候选")
    }
}

/// FR-018 版本标签持久化。
final class VersionLabelStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-vl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    /// 设置后可读回，且持久化到磁盘（新实例可读到）。
    func testSetAndPersist() throws {
        let url = tempDir.appendingPathComponent("labels.json")
        let store = VersionLabelStore(fileURL: url)
        try store.setLabel("校对版", for: "b1")
        XCTAssertEqual(store.label(for: "b1"), "校对版")

        let reloaded = VersionLabelStore(fileURL: url)
        XCTAssertEqual(reloaded.label(for: "b1"), "校对版", "标签应持久化")
    }

    /// 空串 → 清除（回落默认「未命名版本」）。
    func testEmptyLabelClears() throws {
        let url = tempDir.appendingPathComponent("labels.json")
        let store = VersionLabelStore(fileURL: url)
        try store.setLabel("校对版", for: "b1")
        try store.setLabel("   ", for: "b1")
        XCTAssertNil(store.label(for: "b1"), "空白标签应清除")
    }

    /// 未设置返回 nil（调用方回落默认值，我方不预设）。
    func testUnsetReturnsNil() {
        let store = VersionLabelStore(fileURL: tempDir.appendingPathComponent("l.json"))
        XCTAssertNil(store.label(for: "unknown"))
    }
}
