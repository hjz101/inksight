import XCTest
@testable import InkSightAppKit
import Foundation

/// FR-007 epub 解包契约测试（ZipReader + EpubExtractor）。
///
/// **用真实 zip 字节验证**（不是 mock）：解包是二进制格式解析，
/// mock 掉 zip 层就等于什么都没测。
final class EpubExtractorTests: XCTestCase {

    // MARK: - 测试用 zip 构造（stored，不压缩 —— 保证字节可控）

    /// 构造一个 stored（method 0）的 zip 容器。
    static func makeZip(_ files: [(name: String, data: Data)]) -> Data {
        var out = Data()
        var central = Data()

        for f in files {
            let nameBytes = Array(f.name.utf8)
            let offset = out.count
            let crc = crc32(f.data)

            // Local file header
            out.append(contentsOf: [0x50, 0x4b, 0x03, 0x04])   // sig
            out.append(contentsOf: le16(20))                     // version
            out.append(contentsOf: le16(0))                      // flags
            out.append(contentsOf: le16(0))                      // method = stored
            out.append(contentsOf: le16(0))                      // mod time
            out.append(contentsOf: le16(0))                      // mod date
            out.append(contentsOf: le32(crc))
            out.append(contentsOf: le32(UInt32(f.data.count)))   // compressed
            out.append(contentsOf: le32(UInt32(f.data.count)))   // uncompressed
            out.append(contentsOf: le16(UInt16(nameBytes.count)))
            out.append(contentsOf: le16(0))                      // extra len
            out.append(contentsOf: nameBytes)
            out.append(f.data)

            // Central directory entry
            central.append(contentsOf: [0x50, 0x4b, 0x01, 0x02])
            central.append(contentsOf: le16(20))
            central.append(contentsOf: le16(20))
            central.append(contentsOf: le16(0))                  // flags
            central.append(contentsOf: le16(0))                  // method
            central.append(contentsOf: le16(0))
            central.append(contentsOf: le16(0))
            central.append(contentsOf: le32(crc))
            central.append(contentsOf: le32(UInt32(f.data.count)))
            central.append(contentsOf: le32(UInt32(f.data.count)))
            central.append(contentsOf: le16(UInt16(nameBytes.count)))
            central.append(contentsOf: le16(0))                  // extra
            central.append(contentsOf: le16(0))                  // comment
            central.append(contentsOf: le16(0))                  // disk
            central.append(contentsOf: le16(0))                  // internal attrs
            central.append(contentsOf: le32(0))                  // external attrs
            central.append(contentsOf: le32(UInt32(offset)))
            central.append(contentsOf: nameBytes)
        }

        let centralOffset = out.count
        out.append(central)

        // EOCD
        out.append(contentsOf: [0x50, 0x4b, 0x05, 0x06])
        out.append(contentsOf: le16(0))
        out.append(contentsOf: le16(0))
        out.append(contentsOf: le16(UInt16(files.count)))
        out.append(contentsOf: le16(UInt16(files.count)))
        out.append(contentsOf: le32(UInt32(central.count)))
        out.append(contentsOf: le32(UInt32(centralOffset)))
        out.append(contentsOf: le16(0))
        return out
    }

    static func le16(_ v: UInt16) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]
    }
    static func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }
    static func crc32(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1) }
            table[i] = c
        }
        var crc: UInt32 = 0xFFFF_FFFF
        for b in data { crc = table[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }

    // MARK: - ZipReader

    /// 能列出条目并读回内容。
    func testZipReadRoundTrip() throws {
        let zipData = Self.makeZip([
            ("a.txt", Data("hello".utf8)),
            ("dir/b.txt", Data("world".utf8)),
        ])
        let zip = try ZipReader(data: zipData)
        XCTAssertEqual(zip.entries.count, 2)
        XCTAssertEqual(try zip.read("a.txt"), Data("hello".utf8))
        XCTAssertEqual(try zip.read("dir/b.txt"), Data("world".utf8))
    }

    /// 不存在的条目 → 明确报错（不返回空 Data）。
    func testMissingEntryThrows() throws {
        let zip = try ZipReader(data: Self.makeZip([("a.txt", Data("x".utf8))]))
        XCTAssertThrowsError(try zip.read("nope.txt"))
    }

    /// 非 zip 字节 → 明确报错。
    func testNotZipThrows() {
        XCTAssertThrowsError(try ZipReader(data: Data("not a zip".utf8)))
    }

    /// 后缀匹配读取（epub 的 OPF 路径带目录前缀）。
    func testReadFirstMatchingSuffix() throws {
        let zip = try ZipReader(data: Self.makeZip([
            ("OEBPS/content.opf", Data("<package/>".utf8)),
            ("OEBPS/ch1.xhtml", Data("x".utf8)),
        ]))
        let (name, data) = try zip.readFirst(matching: ".opf")
        XCTAssertEqual(name, "OEBPS/content.opf")
        XCTAssertEqual(data, Data("<package/>".utf8))
    }

    // MARK: - EpubExtractor

    private func makeEpub(title: String = "红楼梦",
                          creator: String = "曹雪芹",
                          withCover: Bool = true) -> Data {
        let container = """
        <?xml version="1.0"?>
        <container><rootfiles>
          <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
        </rootfiles></container>
        """
        var files: [(String, Data)] = [("META-INF/container.xml", Data(container.utf8))]

        let manifest = withCover
            ? """
              <item id="cover-img" href="images/cover.jpg" media-type="image/jpeg"/>
              <item id="cover-meta" href="images/cover.jpg" media-type="image/jpeg"/>
              """
            : ""
        let metaCover = withCover ? "<meta name=\"cover\" content=\"cover-img\"/>" : ""
        let opf = """
        <?xml version="1.0"?>
        <package xmlns:dc="http://purl.org/dc/elements/1.1/">
          <metadata>
            <dc:title>\(title)</dc:title>
            <dc:creator>\(creator)</dc:creator>
            \(metaCover)
          </metadata>
          <manifest>
            \(manifest)
          </manifest>
        </package>
        """
        files.append(("OEBPS/content.opf", Data(opf.utf8)))
        if withCover {
            files.append(("OEBPS/images/cover.jpg", Data([0xFF, 0xD8, 0xFF, 0xE0])))
        }
        return Self.makeZip(files)
    }

    /// 完整 epub → 标题/作者/封面全拿到。
    func testExtractFullMetadata() throws {
        let result = try EpubExtractor.extract(from: makeEpub())
        XCTAssertEqual(result.metadata.title, "红楼梦")
        XCTAssertEqual(result.metadata.author, "曹雪芹")
        XCTAssertEqual(result.opfPath, "OEBPS/content.opf")
        XCTAssertEqual(result.metadata.coverImageData, Data([0xFF, 0xD8, 0xFF, 0xE0]),
                       "封面字节应被取出")
    }

    /// 无封面 epub → 标题/作者正常，**封面为 nil（不编造）**。
    func testExtractWithoutCover() throws {
        let result = try EpubExtractor.extract(from: makeEpub(withCover: false))
        XCTAssertEqual(result.metadata.title, "红楼梦")
        XCTAssertNil(result.metadata.coverImageData, "无封面应为 nil，不伪造")
    }

    /// 缺 container.xml 时兜底扫 .opf（部分工具产出如此）。
    func testFallbackWhenNoContainer() throws {
        let opf = """
        <package xmlns:dc="http://purl.org/dc/elements/1.1/">
          <metadata><dc:title>兜底书名</dc:title></metadata></package>
        """
        let zipData = Self.makeZip([("content.opf", Data(opf.utf8))])
        let result = try EpubExtractor.extract(from: zipData)
        XCTAssertEqual(result.metadata.title, "兜底书名", "无 container 应兜底扫 .opf")
    }

    /// OPF 里的相对路径解析（`OEBPS/content.opf` + `images/cover.jpg`）。
    func testHrefResolution() {
        XCTAssertEqual(EpubExtractor.resolve(href: "images/cover.jpg",
                                             relativeTo: "OEBPS/content.opf"),
                       "OEBPS/images/cover.jpg")
        XCTAssertEqual(EpubExtractor.resolve(href: "../cover.jpg",
                                             relativeTo: "OEBPS/content.opf"),
                       "cover.jpg")
        XCTAssertEqual(EpubExtractor.resolve(href: "cover.jpg",
                                             relativeTo: "content.opf"),
                       "cover.jpg", "OPF 在根目录时直接返回")
    }

    /// 完全不是 epub/zip 的字节 → 抛错（不静默返回空元数据）。
    func testNonEpubThrows() {
        XCTAssertThrowsError(try EpubExtractor.extract(from: Data("plain text".utf8)))
    }
}

/// FR-007 集成：导入 .epub 时自动解包取元数据与封面。
final class EpubImportIntegrationTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-epub-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    /// 导入 epub → 书架项带书名/作者/封面。
    func testImportEpubExtractsMetadata() throws {
        let epubData = EpubExtractorTests.makeZip([
            ("META-INF/container.xml", Data("""
            <container><rootfiles>
              <rootfile full-path="content.opf" media-type="application/oebps-package+xml"/>
            </rootfiles></container>
            """.utf8)),
            ("content.opf", Data("""
            <package xmlns:dc="http://purl.org/dc/elements/1.1/">
              <metadata><dc:title>三体</dc:title><dc:creator>刘慈欣</dc:creator>
                <meta name="cover" content="c1"/></metadata>
              <manifest><item id="c1" href="cover.jpg" media-type="image/jpeg"/></manifest>
            </package>
            """.utf8)),
            ("cover.jpg", Data([0xFF, 0xD8, 0xFF, 0xE0])),
        ])
        let url = tempDir.appendingPathComponent("三体.epub")
        try epubData.write(to: url)

        let shelf = BookShelfStore()
        let item = try shelf.importLocalBook(bookID: "e1", title: "", fileURL: url)

        XCTAssertEqual(item.title, "三体", "书名应来自 OPF")
        XCTAssertEqual(item.author, "刘慈欣", "作者应来自 OPF")
        XCTAssertNotNil(item.coverImageData, "封面应被取出")
    }

    /// 非 epub（txt）→ 走文件名推断（不因解包逻辑受影响）。
    func testImportTxtStillUsesFileName() throws {
        let url = tempDir.appendingPathComponent("余华-活着.txt")
        try Data("第一章\n正文".utf8).write(to: url)

        let shelf = BookShelfStore()
        let item = try shelf.importLocalBook(bookID: "t1", title: "", fileURL: url)
        XCTAssertEqual(item.author, "余华", "txt 仍走文件名推断")
        XCTAssertNil(item.coverImageData, "txt 无封面")
    }

    /// 损坏的 epub → **不阻断导入**（回落文件名，诚实降级）。
    func testCorruptEpubFallsBackGracefully() throws {
        let url = tempDir.appendingPathComponent("坏书.epub")
        try Data("this is not a zip".utf8).write(to: url)

        let shelf = BookShelfStore()
        let item = try shelf.importLocalBook(bookID: "bad", title: "", fileURL: url)
        XCTAssertEqual(item.title, "坏书", "解包失败应回落文件名（不阻断导入）")
        XCTAssertNil(item.coverImageData)
    }
}
