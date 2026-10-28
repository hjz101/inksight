import XCTest
@testable import InkSightAppKit
import InkSightCore

/// FR-024b 在线进度映射契约测试。
final class OnlineProgressMapperTests: XCTestCase {

    private var tempDir: URL!
    private var cache: SQLiteCache!
    private var mapper: OnlineProgressMapper!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-fr024b-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        cache = try SQLiteCache(databaseURL: tempDir.appendingPathComponent("c.db"))
        mapper = OnlineProgressMapper(cache: cache)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    /// 记录映射 → 按章读取 → 偏移完整还原。
    func testRecordThenRead() {
        XCTAssertNoThrow(try mapper.record(bookID: "b", chapterID: 5, title: "第五章",
                                           charOffset: 123,
                                           bodyStart: "开头一段话", bodyEnd: "结尾一段话").get())
        XCTAssertEqual(mapper.mapping(bookID: "b", chapterID: 5)?.charOffset, 123)
        XCTAssertEqual(mapper.mapping(bookID: "b", chapterID: 5)?.startFingerprint,
                       Fingerprint.fnv1a64("开头一段话"), "只存指纹不存正文")
    }

    /// 换源对齐：目标章首片段与映射指纹匹配 → 返回旧偏移。
    func testAlignByStartFingerprint() {
        XCTAssertNoThrow(try mapper.record(bookID: "b", chapterID: 2, title: "第二章",
                                           charOffset: 456,
                                           bodyStart: "换源后的开头", bodyEnd: "结尾").get())
        XCTAssertEqual(mapper.align(bookID: "b", targetStart: "换源后的开头", targetEnd: "不同结尾"),
                       456, "首指纹匹配应返回旧偏移")
    }

    /// 首指纹不匹配但尾指纹匹配 → 仍能对齐（容忍标题/开头漂移）。
    func testAlignByEndFingerprint() {
        XCTAssertNoThrow(try mapper.record(bookID: "b", chapterID: 3, title: "第三章",
                                           charOffset: 789,
                                           bodyStart: "旧开头", bodyEnd: "稳定结尾").get())
        XCTAssertEqual(mapper.align(bookID: "b", targetStart: "漂移后的开头", targetEnd: "稳定结尾"),
                       789, "尾指纹匹配应返回旧偏移")
    }

    /// 首尾都不匹配 → 返回 nil（诚实：不强行对齐）。
    func testAlignNoMatchReturnsNil() {
        XCTAssertNoThrow(try mapper.record(bookID: "b", chapterID: 1, title: "第一章",
                                           charOffset: 10, bodyStart: "A", bodyEnd: "B").get())
        XCTAssertNil(mapper.align(bookID: "b", targetStart: "完全不同的开头", targetEnd: "完全不同的结尾"))
    }

    /// 幂等覆盖：同一章重复记录以最新为准。
    func testRecordIsIdempotentOverwrite() {
        XCTAssertNoThrow(try mapper.record(bookID: "b", chapterID: 1, title: "第一章",
                                           charOffset: 10, bodyStart: "A", bodyEnd: "B").get())
        XCTAssertNoThrow(try mapper.record(bookID: "b", chapterID: 1, title: "第一章",
                                           charOffset: 99, bodyStart: "A", bodyEnd: "B").get())
        XCTAssertEqual(mapper.mapping(bookID: "b", chapterID: 1)?.charOffset, 99, "重复记录应覆盖")
    }
}
