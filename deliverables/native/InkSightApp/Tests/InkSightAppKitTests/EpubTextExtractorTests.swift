import XCTest
@testable import InkSightAppKit
import Foundation

/// FR-007 epub **正文提取**契约测试（D-101：epub 从"只能看封面"到"能读内容"）。
final class EpubTextExtractorTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-epubtext-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func makeEpub(chapters: [(title: String, body: String)]) -> Data {
        let container = """
        <container><rootfiles>
          <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
        </rootfiles></container>
        """
        var manifestItems = ""
        var spineItems = ""
        var files: [(String, Data)] = [("META-INF/container.xml", Data(container.utf8))]

        for (i, ch) in chapters.enumerated() {
            manifestItems += "<item id=\"ch\(i)\" href=\"ch\(i).xhtml\" media-type=\"application/xhtml+xml\"/>\n"
            spineItems += "<itemref idref=\"ch\(i)\"/>\n"
            // 纯图片页（body 只含 img，无标题文字）用空 title 标记，
            // 用于验证"空章跳过"——若这里仍插入 <h1> 标题，就不是纯图片页了。
            let heading = ch.title.isEmpty ? "" : "<h1>\(ch.title)</h1>"
            let xhtml = """
            <?xml version="1.0"?>
            <html><head><title>\(ch.title)</title></head>
            <body>\(heading)\(ch.body)</body></html>
            """
            files.append(("OEBPS/ch\(i).xhtml", Data(xhtml.utf8)))
        }

        let opf = """
        <package xmlns:dc="http://purl.org/dc/elements/1.1/">
          <metadata><dc:title>测试书</dc:title></metadata>
          <manifest>\(manifestItems)</manifest>
          <spine>\(spineItems)</spine>
        </package>
        """
        files.append(("OEBPS/content.opf", Data(opf.utf8)))
        return EpubExtractorTests.makeZip(files)
    }

    /// 按 spine 顺序提取全部章节正文。
    func testExtractsAllSpineChapters() throws {
        let data = makeEpub(chapters: [
            ("第一章", "<p>第一章的内容。</p>"),
            ("第二章", "<p>第二章的内容。</p>"),
        ])
        let result = try EpubTextExtractor.extract(from: data)
        XCTAssertTrue(result.text.contains("第一章的内容"))
        XCTAssertTrue(result.text.contains("第二章的内容"))
        XCTAssertEqual(result.chapterTitles, ["第一章", "第二章"], "章节顺序须按 spine")
    }

    /// **段落边界换行**（否则全文粘成一行）。
    func testParagraphBoundariesBecomeNewlines() throws {
        let data = makeEpub(chapters: [("章", "<p>段落一。</p><p>段落二。</p>")])
        let result = try EpubTextExtractor.extract(from: data)
        XCTAssertTrue(result.text.contains("段落一。\n段落二。")
                      || result.text.contains("段落一。\n\n段落二。"),
                      "两个 <p> 之间必须有换行，实际：\(result.text.debugDescription)")
    }

    /// HTML 实体解码。
    func testEntityDecoding() throws {
        let data = makeEpub(chapters: [("章", "<p>A&amp;B &lt;tag&gt; &quot;引号&quot;</p>")])
        let result = try EpubTextExtractor.extract(from: data)
        XCTAssertTrue(result.text.contains("A&B"), "&amp; 须解码")
        XCTAssertTrue(result.text.contains("<tag>"), "&lt;/&gt; 须解码")
        XCTAssertTrue(result.text.contains("\"引号\""), "&quot; 须解码")
    }

    /// script/style 内容不进正文。
    func testScriptAndStyleStripped() throws {
        let data = makeEpub(chapters: [
            ("章", "<style>body{color:red}</style><script>var x=1</script><p>真正文</p>")
        ])
        let result = try EpubTextExtractor.extract(from: data)
        XCTAssertTrue(result.text.contains("真正文"))
        XCTAssertFalse(result.text.contains("color:red"), "style 内容不得进正文")
        XCTAssertFalse(result.text.contains("var x=1"), "script 内容不得进正文")
    }

    /// 空章（纯图片页）跳过，不产生空章节。
    func testEmptyChaptersSkipped() throws {
        let data = makeEpub(chapters: [
            ("", "<div><img src='c.jpg'/></div>"),
            ("正文", "<p>有内容的章节。</p>"),
        ])
        let result = try EpubTextExtractor.extract(from: data)
        XCTAssertTrue(result.text.contains("有内容的章节"))
        XCTAssertEqual(result.chapterTitles, ["正文"], "无文字章节应跳过（只剩有内容的章）")
    }

    /// 无 spine → 明确抛错（不返回空文本假装成功）。
    func testNoSpineThrows() {
        let files: [(String, Data)] = [
            ("META-INF/container.xml", Data("<container><rootfiles><rootfile full-path='c.opf'/></rootfiles></container>".utf8)),
            ("c.opf", Data("<package><manifest></manifest></package>".utf8)),
        ]
        XCTAssertThrowsError(try EpubTextExtractor.extract(from: EpubExtractorTests.makeZip(files)))
    }

    /// 非 epub → 抛错。
    func testNonEpubThrows() {
        XCTAssertThrowsError(try EpubTextExtractor.extract(from: Data("plain".utf8)))
    }

    // MARK: - 端到端：epub → 导入 → 可读正文

    /// **闭环**：导入 epub 后 `chapterText` 能取到正文（此前是 nil）。
    func testEndToEndEpubIsReadable() throws {
        let epubData = makeEpub(chapters: [
            ("第一章 起点", "<p>这是第一章的正文内容。</p>"),
            ("第二章 继续", "<p>这是第二章的正文内容。</p>"),
        ])
        let url = tempDir.appendingPathComponent("可读书.epub")
        try epubData.write(to: url)

        let shelf = BookShelfStore()
        let item = try shelf.importLocalBook(bookID: "readable-\(UUID().uuidString)",
                                             title: "", fileURL: url)

        XCTAssertGreaterThan(item.chapterCount, 0, "epub 应扫出章节")
        let text = try XCTUnwrap(shelf.chapterText(for: item, chapterIndex: 0),
                                 "epub 第一章正文应可读（D-101 的核心）")
        XCTAssertTrue(text.contains("第一章的正文内容"), "正文内容应正确，实际：\(text)")
    }

    /// epub 元数据与正文**同时**到位。
    func testEndToEndMetadataAndContent() throws {
        let epubData = makeEpub(chapters: [("章", "<p>内容</p>")])
        let url = tempDir.appendingPathComponent("书.epub")
        try epubData.write(to: url)

        let shelf = BookShelfStore()
        let item = try shelf.importLocalBook(bookID: "both-\(UUID().uuidString)",
                                             title: "", fileURL: url)
        XCTAssertEqual(item.title, "测试书", "书名来自 OPF")
        XCTAssertNotNil(shelf.chapterText(for: item, chapterIndex: 0), "正文也可读")
    }
}
