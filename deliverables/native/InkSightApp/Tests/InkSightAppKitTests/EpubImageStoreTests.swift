import XCTest
@testable import InkSightAppKit
import Foundation

/// FR-018-ac b 图片缓存契约测试（占位块点击进全屏原图的数据源）。
final class EpubImageStoreTests: XCTestCase {

    private var bookID: String!

    override func setUpWithError() throws {
        bookID = "imgtest-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        if let bookID { EpubImageStore.clear(bookID: bookID) }
    }

    private func jpeg(_ marker: UInt8) -> Data {
        Data([0xFF, 0xD8, 0xFF, marker, 0x00, 0x11])
    }
    private func png(_ marker: UInt8) -> Data {
        Data([0x89, 0x50, 0x4E, 0x47, marker, 0x00])
    }

    /// 保存后按序号取回，字节一致。
    func testSaveAndLoadByIndex() throws {
        let a = jpeg(0x01), b = png(0x02)
        let written = try EpubImageStore.save(images: [a, b], bookID: bookID)
        XCTAssertEqual(written, 2)

        XCTAssertEqual(EpubImageStore.image(at: 0, bookID: bookID), a)
        XCTAssertEqual(EpubImageStore.image(at: 1, bookID: bookID), b)
    }

    /// **顺序位保持**：中间某张取不到时，后续图片**不左移**。
    ///
    /// 左移会让"占位标记第 2 个"配上第 1 张图 —— 视觉上"图不对文"。
    func testMissingImageDoesNotShiftIndices() throws {
        let a = jpeg(0x01), c = jpeg(0x03)
        // 索引 1 为 nil（源缺失），索引 2 有图
        let written = try EpubImageStore.save(images: [a, nil, c], bookID: bookID)
        XCTAssertEqual(written, 2, "只写实有的两张")

        XCTAssertEqual(EpubImageStore.image(at: 0, bookID: bookID), a)
        XCTAssertNil(EpubImageStore.image(at: 1, bookID: bookID), "缺失位应为 nil")
        XCTAssertEqual(EpubImageStore.image(at: 2, bookID: bookID), c,
                       "索引 2 必须仍是 c，不得左移")
    }

    /// 未保存的序号返回 nil（诚实，不返回空 Data）。
    func testUnknownIndexReturnsNil() {
        XCTAssertNil(EpubImageStore.image(at: 99, bookID: bookID))
    }

    /// 扩展名按 magic bytes 判定（存/取同规则 → 能取回）。
    func testExtensionDetection() throws {
        XCTAssertEqual(EpubImageStore.ext(for: jpeg(0)), ".jpg")
        XCTAssertEqual(EpubImageStore.ext(for: png(0)), ".png")
        XCTAssertEqual(EpubImageStore.ext(for: Data([0x47, 0x49, 0x46, 0x38])), ".gif")

        // 三种格式都能存能取
        let images = [jpeg(0x11), png(0x22), Data([0x47, 0x49, 0x46, 0x38, 0x00])]
        try EpubImageStore.save(images: images, bookID: bookID)
        for (i, expected) in images.enumerated() {
            XCTAssertEqual(EpubImageStore.image(at: i, bookID: bookID), expected,
                           "第 \(i) 张（含扩展名判定）应能取回")
        }
    }

    /// 清空后取不到。
    func testClear() throws {
        try EpubImageStore.save(images: [jpeg(1)], bookID: bookID)
        EpubImageStore.clear(bookID: bookID)
        XCTAssertNil(EpubImageStore.image(at: 0, bookID: bookID))
    }

    /// 不同书互不干扰（目录按 bookID 哈希隔离）。
    func testBooksAreIsolated() throws {
        let other = "other-\(UUID().uuidString)"
        defer { EpubImageStore.clear(bookID: other) }
        try EpubImageStore.save(images: [jpeg(0xAA)], bookID: bookID)
        try EpubImageStore.save(images: [jpeg(0xBB)], bookID: other)

        XCTAssertEqual(EpubImageStore.image(at: 0, bookID: bookID), jpeg(0xAA))
        XCTAssertEqual(EpubImageStore.image(at: 0, bookID: other), jpeg(0xBB))
    }
}
