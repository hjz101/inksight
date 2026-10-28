import XCTest
@testable import InkSightCore

/// AC-1（技术约束清单 FR-031 原文）：喂 `<p style="font-size:20px;text-indent:2em">`，
/// 断言 `sourceStyleResidual == 0`。
/// `strippedStyleCount > 0` 只进调试面板，**不设阈值、不进验收**（观测项）。
final class StyleStripperTests: XCTestCase {

    /// AC-1 主判据。
    func testAC1StyleResidualIsZero() {
        let outcome = StyleStripper.strip(
            html: "<p style=\"font-size:20px;text-indent:2em\">他推开门，风从门缝里钻进来。</p>"
        )
        XCTAssertEqual(outcome.sourceStyleResidual, 0, "AC-1：渲染输入中残留源样式必须为 0")
        XCTAssertGreaterThan(outcome.strippedStyleCount, 0, "观测项：解析器确实剥离过样式（应 > 0）")
        XCTAssertEqual(outcome.paragraphs.count, 1)
        XCTAssertEqual(outcome.paragraphs[0].text, "他推开门，风从门缝里钻进来。")
        XCTAssertEqual(outcome.paragraphs[0].kind, .text)
    }

    /// AC 反向激励防护：strippedStyleCount 是"剥离了多少"的观测量，归零说明解析器没生效。
    func testStrippedStyleCountMustBePositiveWhenStylePresent() {
        let outcome = StyleStripper.strip(html: "<p style=\"color:red\">红字。</p>")
        XCTAssertGreaterThan(outcome.strippedStyleCount, 0, "有源样式却计 0 = 解析器未生效")
    }

    func testImageParagraph() {
        let outcome = StyleStripper.strip(html: "<p>前面一段。</p><p><img src=\"cover.jpg\" alt=\"封面\"></p>")
        XCTAssertEqual(outcome.paragraphs.count, 2)
        XCTAssertEqual(outcome.paragraphs[1].kind, .image)
        XCTAssertEqual(outcome.paragraphs[1].imageReferences, ["cover.jpg"])
        XCTAssertEqual(outcome.sourceStyleResidual, 0)
    }

    func testTitleParagraph() {
        let outcome = StyleStripper.strip(html: "<h2>第一章 风起</h2><p>正文跟在标题后。</p>")
        XCTAssertEqual(outcome.paragraphs[0].kind, .title)
        XCTAssertEqual(outcome.paragraphs[0].text, "第一章 风起")
        XCTAssertEqual(outcome.paragraphs[1].kind, .text)
    }

    /// 无标签纯文本 → 单个 text 段。
    func testPlainTextPassThrough() {
        let outcome = StyleStripper.strip(html: "纯文本段落，没有任何标签。")
        XCTAssertEqual(outcome.paragraphs.count, 1)
        XCTAssertEqual(outcome.paragraphs[0].kind, .text)
        XCTAssertEqual(outcome.paragraphs[0].text, "纯文本段落，没有任何标签。")
        XCTAssertEqual(outcome.sourceStyleResidual, 0)
    }

    /// `<script>`/`<style>` 整块丢弃：内部文本不进段落，也不计残差。
    func testScriptAndStyleBlocksDropped() {
        let outcome = StyleStripper.strip(
            html: "<p>正常段落。</p><style>p{font-size:20px}</style><script>var a=1;</script><p>第二段。</p>"
        )
        XCTAssertEqual(outcome.paragraphs.count, 2)
        XCTAssertEqual(outcome.sourceStyleResidual, 0)
        XCTAssertFalse(outcome.paragraphs.contains { $0.text.contains("font-size") || $0.text.contains("var a") })
    }

    /// 残差观测：**若实现泄漏样式，residual 必须 > 0 才有意义**——
    /// 这里验证残差检测器本身是活的（喂一个会泄漏的输入给内部缓冲，间接保障检测器不恒为 0）。
    func testResidualDetectorIsAlive() {
        // 构造：标签属性里没有 style 关键字、但正文里带 style= 文本（解析器按纯文本透传）
        let outcome = StyleStripper.strip(html: "<p>这段正文里本身写着 style= 三个字母。</p>")
        // 文本内容里的 "style=" 属于**用户内容**，不剥离（我方不替代用户改内容），
        // 但残差检测器必须能看见它——否则检测器是死的。
        XCTAssertGreaterThan(outcome.sourceStyleResidual, 0, "残差检测器失效（对正文中的标记不可见）")
    }
}
