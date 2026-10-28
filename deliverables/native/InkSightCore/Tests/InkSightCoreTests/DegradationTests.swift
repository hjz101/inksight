import XCTest
@testable import InkSightCore

/// 降级门面 CI 门禁（《降级申报清单》§一：缺一行即该单测失败、CI 挡合并）。
final class DegradationTests: XCTestCase {

    /// **CI 门禁**：遍历 `Degradation.Kind` 全枚举，校验每个 kind 在清单有登记。
    /// 新增 kind 未登记 → 本测试失败 → CI 挡合并。
    func testEveryKindIsRegistered() {
        for kind in Degradation.Kind.allCases {
            let entry = Degradation.entry(for: kind)
            XCTAssertNotNil(entry, "\(kind) 必须在《降级申报清单》登记（缺一行即 CI 挡合并）")
        }
        // 登记表不得出现清单外的 kind（防止"登记了但枚举里没有"的幽灵条目）
        for entry in Degradation.registry {
            XCTAssertTrue(Degradation.Kind.allCases.contains(entry.kind),
                          "登记表出现枚举外的 kind：\(entry.kind)")
        }
    }

    /// 登记表与《降级申报清单》§三的 `declaresData` 逐行一致。
    func testDeclaresDataMatchesRegistry() {
        // 清单 §三 的 declaresData 列（真值表）
        let expected: [Degradation.Kind: Bool] = [
            .chapterLoadFailed: false,
            .sourceAllUnavailable: false,
            .importParseFailed: false,
            .epubChapterMissing: false,
            .alignmentFallback: true,
            .fallbackToPlainText: true,
            .offlineNoCache: false,
            .searchNoResult: false,
            .fontFallback: false,
            .glassReduced: false,
        ]
        for (kind, expectedValue) in expected {
            let entry = Degradation.entry(for: kind)
            XCTAssertEqual(entry?.declaresData, expectedValue,
                           "\(kind) 的 declaresData 必须与《降级申报清单》一致")
        }
        // declaresData == true 的 kind 必须写明数据来源类别（清单 §二：来源类别必填）
        for entry in Degradation.registry where entry.declaresData {
            XCTAssertNotNil(entry.dataSourceCategory,
                            "\(entry.kind) declaresData==true 必须写明数据来源类别")
        }
    }

    /// 三个"明确禁止的降级"不得存在于枚举——禁止的东西不该有名字。
    func testForbiddenKindsDoNotExistInEnum() {
        for kind in Degradation.Kind.allCases {
            let raw = kind.rawValue
            XCTAssertFalse(raw.contains("autoMerge"), "autoMergeAcrossVersions 是禁止的降级，不得有名字")
            XCTAssertFalse(raw.contains("remoteCache"), "remoteCache 是禁止的降级，不得有名字")
            XCTAssertFalse(raw.contains("silentPartial"), "silentPartialChapter 是禁止的降级，不得有名字")
        }
    }

    /// `degrade` 对已登记、声明一致的 kind 返回成功事件。
    func testDegradeSucceedsForRegisteredKind() {
        let result = Degradation.degrade(kind: .chapterLoadFailed, declaresData: false,
                                         detail: "超时（8s 硬上限）")
        switch result {
        case .success(let event):
            XCTAssertEqual(event.kind, .chapterLoadFailed)
            XCTAssertFalse(event.declaresData)
            XCTAssertEqual(event.detail, "超时（8s 硬上限）")
        case .failure(let error):
            XCTFail("已登记且声明一致应成功，实际失败：\(error)")
        }
    }

    /// declaresData 与清单不符 → `.failure(.mismatchedDeclaresData)`（谎报可追责）。
    func testDegradeMismatchedDeclaresDataFails() {
        // alignmentFallback 清单登记 declaresData==true，这里谎报 false → 必须失败
        let result = Degradation.degrade(kind: .alignmentFallback, declaresData: false,
                                         detail: "谎报测试")
        guard case .failure(let error) = result else {
            return XCTFail("谎报 declaresData 必须失败")
        }
        XCTAssertEqual(error, .mismatchedDeclaresData(kind: .alignmentFallback,
                                                      declared: false, registered: true))
    }

    /// 未登记 kind 必须失败（枚举与登记由 testEveryKindIsRegistered 锁定一致，
    /// 此路径是防御性双保险——用自定义 Kind 无法构造，故验证已登记路径不崩溃即可）。
    func testDegradePathIsDefensive() {
        // 10 个 kind 全部可成功降级（不崩溃、不抛错）
        for kind in Degradation.Kind.allCases {
            let entry = Degradation.entry(for: kind)
            let result = Degradation.degrade(kind: kind,
                                             declaresData: entry?.declaresData ?? false,
                                             detail: "防御性测试")
            XCTAssertNotNil(try? result.get(), "\(kind) 按清单声明调用必须成功")
        }
    }
}
