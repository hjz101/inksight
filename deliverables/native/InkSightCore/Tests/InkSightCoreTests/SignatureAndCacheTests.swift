import XCTest
@testable import InkSightCore
import CoreText
import Foundation

/// 签名与缓存失效：签名变化 → 同步作废全部缓存 O(1)（技术约束清单 TypographySignature 原文）；
/// 禁则表版本变化 → anchor 失效重算。
final class SignatureAndCacheTests: XCTestCase {

    private let typography = ReaderTypography(
        fontID: "PingFangSC-Regular", fontSize: 20, lineHeightMultiplier: 1.75,
        paragraphSpacingBefore: 12, paragraphSpacingAfter: 0,
        insets: ReaderInsets(top: 24, leading: 20, bottom: 28, trailing: 20),
        indent: 0, imagePlaceholderAspect: 0.75
    )
    private let container = CGSize(width: 393, height: 852)

    /// 签名字段清单（冻结契约）里**任何一个字段变化 → 哈希必变**。
    func testEveryFieldChangeChangesSignature() {
        let base = TypographySignature(typography: typography, containerSize: container,
                                       screenScale: 3, kinsokuVersion: 1)
        func make(_ mutate: (inout ReaderTypography) -> Void = { _ in },
                  size: CGSize? = nil, scale: Double? = nil, kinsoku: Int? = nil) -> TypographySignature {
            var t = typography
            mutate(&t)
            return TypographySignature(typography: t,
                                       containerSize: size ?? self.container,
                                       screenScale: scale ?? 3, kinsokuVersion: kinsoku ?? 1)
        }
        let variants: [TypographySignature] = [
            make { $0.fontID = "SourceHanSerifSC-Regular" },
            make { $0.fontSize = 21 },
            make { $0.lineHeightMultiplier = 1.70 },
            make { $0.paragraphSpacingBefore = 0 },
            make { $0.paragraphSpacingAfter = 4 },
            make { $0.insets.top = 30 },
            make { $0.insets.leading = 16 },
            make { $0.insets.bottom = 30 },
            make { $0.insets.trailing = 16 },
            make { $0.indent = 40 },
            make { $0.imagePlaceholderAspect = 4.0 / 3.0 },
            make(size: CGSize(width: 375, height: 812)),   // containerSize
            make(scale: 2),                                     // screenScale
            make(kinsoku: 2),                                   // 禁则表版本号
        ]
        for (i, variant) in variants.enumerated() {
            XCTAssertNotEqual(variant, base, "第 \(i) 个变体的签名与基线相同（哈希漏字段）")
            XCTAssertNotEqual(variant.digest, base.digest, "第 \(i) 个变体哈希未变（字段清单有漏）")
        }
    }

    /// 哈希确定性：同输入必同输出（Locale 不漂移——fixed6 用 en_US_POSIX）。
    func testSignatureIsDeterministic() {
        let a = TypographySignature(typography: typography, containerSize: container, screenScale: 3, kinsokuVersion: 1)
        let b = TypographySignature(typography: typography, containerSize: container, screenScale: 3, kinsokuVersion: 1)
        XCTAssertEqual(a.digest, b.digest)
    }

    /// 禁则表版本变化 → anchor 失效重算（契约：禁则表版本入签名）。
    /// 构造受控输入：宽度 160pt（8 字 × 20pt）、行盒 35pt × 3 行页，
    /// 文本循环「甲乙丙丁戊己庚辛：壬癸」——v1 在第 8 字后断行（「：」合法起行），
    /// v2 把「：」入行首禁则 → 悬挂 → 断点前移 1 字 → 第 2 页起点 24 → 25，anchor 必不同。
    func testKinsokuVersionChangeInvalidatesAnchors() {
        let text = String(repeating: "甲乙丙丁戊己庚辛：壬癸", count: 3)
        let noInsets = ReaderTypography(
            fontID: "PingFangSC-Regular", fontSize: 20, lineHeightMultiplier: 1.75,
            paragraphSpacingBefore: 0, paragraphSpacingAfter: 0,
            insets: ReaderInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
            indent: 0, imagePlaceholderAspect: 0.75
        )
        let size = CGSize(width: 160, height: 105)   // 3 行 × 35pt
        let resultV1 = Typesetter(text: text, typography: noInsets, containerSize: size,
                                  kinsoku: .v1).typesetChapter()
        // v2 的构造：把「己」加入**行尾**禁则。实测 v1 的断点形态是
        // 行1 [0,9)（「：」悬挂到行尾）、行2 [9,17)（行尾「己」）、行3 [17,25)——
        // 行尾真的会出现「己」，所以这条禁则会咬人。
        // （第一次构造把「：」加进行首禁则是 no-op——v1 行首禁则本来就含「：」，
        //   被测试当场抓出：改规则前先确认它防的风险真的存在。）
        var kinsokuV2 = Kinsoku.v1
        kinsokuV2 = Kinsoku(version: 2,
                            lineStartForbidden: kinsokuV2.lineStartForbidden,
                            lineEndForbidden: kinsokuV2.lineEndForbidden.union(["己"]))
        let resultV2 = Typesetter(text: text, typography: noInsets, containerSize: size,
                                  kinsoku: kinsokuV2).typesetChapter()

        let anchorsV1 = resultV1.pages.map(\.anchor)
        let anchorsV2 = resultV2.pages.map(\.anchor)
        // v1 在「：」合法起行；v2 悬挂「：」→ 全部断点错位
        XCTAssertNotEqual(anchorsV1, anchorsV2,
            "禁则表 v1→v2 断点发生变化，anchor 必须重算（若相同说明禁则表未真正参与断点裁决）")
        // 语义不变量在两个版本下都必须保持（FR-031 与避头尾）
        XCTAssertLessThanOrEqual(resultV1.fr031MaxDelta, 0.5)
        XCTAssertLessThanOrEqual(resultV2.fr031MaxDelta, 0.5)
        // 实质判定：v2 的锚点偏移集合不得与 v1 完全重合（至少一处断点不同）
        XCTAssertNotEqual(Set(anchorsV1.map(\.charOffset)), Set(anchorsV2.map(\.charOffset)))
    }

    /// PageAnchorCache：LRU 10 章 + O(1) 全作废（签名变化即调用）。
    func testPageAnchorCacheLRUAndInvalidation() {
        let cache = PageAnchorCache()
        let hash = "sig-a"
        for chapter in 0..<12 {
            cache.store([PageAnchor(chapterID: chapter, charOffset: 0, charLength: 100,
                                    lineCount: 4, fingerprint: UInt64(chapter))],
                        for: chapter, signatureHash: hash)
        }
        // 容量 10：最早写入的两章（0、1）应被淘汰
        XCTAssertNil(cache.anchors(for: 0, signatureHash: hash))
        XCTAssertNil(cache.anchors(for: 1, signatureHash: hash))
        XCTAssertNotNil(cache.anchors(for: 11, signatureHash: hash))

        // 签名变化 → invalidateAll（O(1)）→ 全部失效
        cache.invalidateAll()
        for chapter in 2..<12 {
            XCTAssertNil(cache.anchors(for: chapter, signatureHash: hash), "invalidateAll 后不得残留旧条目")
        }
        // 新签名可重新装载
        cache.store([PageAnchor(chapterID: 3, charOffset: 0, charLength: 99, lineCount: 3, fingerprint: 1)],
                    for: 3, signatureHash: "sig-b")
        XCTAssertNotNil(cache.anchors(for: 3, signatureHash: "sig-b"))
    }

    /// CTFrameCache：按页 LRU 7 页（D-52 勘误值）+ invalidateAll。
    /// 注意：断言用 XCTAssertTrue/False 而非 XCTAssertNil——Nil 断言的失败信息会打印
    /// CTFrame 的完整 debug description（数千行 glyph 表），反而淹没结果。
    func testCTFrameCacheLRUCapacity7() {
        let sampleText = String(repeating: "一段用来建帧的正文。", count: 300)
        let typesetter = Typesetter(text: sampleText, typography: typography,
                                    containerSize: container, kinsoku: .v1)
        let cache = CTFrameCache()
        let hash = "sig-frame"
        let total = (sampleText as NSString).length
        var keys: [CTFrameCacheKey] = []
        var cursor = 0
        while keys.count < 8, cursor < total {
            keys.append(CTFrameCacheKey(chapterID: 0, charOffset: cursor, signatureHash: hash))
            cursor += 120
        }
        XCTAssertEqual(keys.count, 8, "样本须足够产出 8 个不同 key（否则 LRU 测不到淘汰）")
        for key in keys {
            cache.store(typesetter.makeFrame(location: key.charOffset, length: 120), for: key)
        }
        XCTAssertTrue(cache.frame(for: keys[0]) == nil, "容量 7：第 1 帧必须被 LRU 淘汰")
        XCTAssertTrue(cache.frame(for: keys[1]) != nil, "第 2 帧应仍在")
        XCTAssertTrue(cache.frame(for: keys[7]) != nil, "最新帧必须在")

        cache.invalidateAll()
        for key in keys {
            XCTAssertTrue(cache.frame(for: key) == nil, "invalidateAll 后不得残留 CTFrame（合规四禁令之释放要求）")
        }
    }
}
