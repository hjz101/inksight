import XCTest
@testable import InkSightAppKit
import Foundation

/// AGE_MATRIX v1.1 §1 两张表逐格对抄（8 个 (state, variant) 单元格）＋ 不变式逐条判定。
final class AgeGateMatrixTests: XCTestCase {

    private func assertCell(_ state: AgeGateState, _ variant: BuildVariant,
                            curfew: Bool, quota: Bool,
                            importFiles: Presence, online: Presence, path: Presence,
                            autoExit: AutoExitPolicy,
                            file: StaticString = #filePath, line: UInt = #line) {
        let cell = AgeGateMatrix.cell(state: state, variant: variant)
        XCTAssertEqual(cell.curfew, curfew, "\(state)/\(variant) curfew", file: file, line: line)
        XCTAssertEqual(cell.dailyQuota, quota, "\(state)/\(variant) quota", file: file, line: line)
        XCTAssertEqual(cell.importFiles, importFiles, "\(state)/\(variant) import", file: file, line: line)
        XCTAssertEqual(cell.onlineSources, online, "\(state)/\(variant) online", file: file, line: line)
        XCTAssertEqual(cell.settingsPath, path, "\(state)/\(variant) path", file: file, line: line)
        XCTAssertEqual(cell.autoExit, autoExit, "\(state)/\(variant) autoExit", file: file, line: line)
    }

    /// AGE_MATRIX §1 release 表。
    func testReleaseMatrix() {
        assertCell(.adultConfirmed, .release, curfew: false, quota: false,
                   importFiles: .granted, online: .absent, path: .absent, autoExit: .notApplicable)
        assertCell(.minorConfirmed, .release, curfew: true, quota: true,
                   importFiles: .absent, online: .absent, path: .absent, autoExit: .never)
        assertCell(.ageUnresolved, .release, curfew: true, quota: false,
                   importFiles: .granted, online: .absent, path: .granted, autoExit: .retryUntilResolved)
        assertCell(.unverified, .release, curfew: false, quota: false,
                   importFiles: .granted, online: .absent, path: .granted, autoExit: .onDidBecomeActive)
    }

    /// AGE_MATRIX §1 research 表。
    func testResearchMatrix() {
        assertCell(.adultConfirmed, .research, curfew: false, quota: false,
                   importFiles: .granted, online: .granted, path: .absent, autoExit: .notApplicable)
        assertCell(.minorConfirmed, .research, curfew: true, quota: true,
                   importFiles: .absent, online: .restricted, path: .absent, autoExit: .never)
        assertCell(.ageUnresolved, .research, curfew: true, quota: false,
                   importFiles: .granted, online: .restricted, path: .granted, autoExit: .retryUntilResolved)
        assertCell(.unverified, .research, curfew: false, quota: false,
                   importFiles: .granted, online: .restricted, path: .granted, autoExit: .onDidBecomeActive)
    }

    /// 不变式 1：`.minorConfirmed` 下 ∅ 单元格 = 导入/在线/系统路径 → 界面不出现这些能力。
    func testMinorConfirmedAbilitiesAreStructurallyAbsent() {
        for variant in BuildVariant.allCases {
            let cell = AgeGateMatrix.cell(state: .minorConfirmed, variant: variant)
            XCTAssertEqual(cell.importFiles, .absent)
            XCTAssertEqual(cell.settingsPath, .absent)
            // ∅ 的 UI 表现是"结构上不生成"：路径文本必须为 nil（连空串都不给）
            XCTAssertNil(AgeGateMatrix.settingsPathText(state: .minorConfirmed, variant: variant,
                                                        provider: BundledSettingsPathProvider()))
        }
    }

    /// 不变式 2：release 变体下"在线书源"全 ∅ → 任何"在线功能不可用"字样均不得出现。
    func testReleaseNeverMentionsOnline() {
        for state in AgeGateState.allCases {
            if let banner = AgeGateMatrix.bannerText(state: state, variant: .release) {
                XCTAssertFalse(banner.contains("在线"), "release 下 \(state) 的状态条不得提在线：\(banner)")
            }
            for curtain in AgeGateMatrix.curtainVariants(state: state, variant: .release) {
                XCTAssertFalse(curtain.title.contains("在线"), "release 拦截页标题不得提在线")
                XCTAssertFalse(curtain.caption.contains("在线"), "release 拦截页副文案不得提在线")
            }
        }
    }

    /// 不变式 3：`.minorConfirmed` 自动退出恒为"无"。
    func testMinorConfirmedNeverAutoExits() {
        for variant in BuildVariant.allCases {
            XCTAssertEqual(AgeGateMatrix.cell(state: .minorConfirmed, variant: variant).autoExit, .never)
        }
    }

    /// 不变式 4：`.ageUnresolved` 宵禁 ✓ 而 `.unverified` 宵禁 ✗ → 不存在自动降级。
    func testNoCurfewDowngradePath() {
        XCTAssertTrue(AgeGateMatrix.cell(state: .ageUnresolved, variant: .release).curfew)
        XCTAssertFalse(AgeGateMatrix.cell(state: .unverified, variant: .release).curfew)
        // 自动退出策略：ageUnresolved 重试、unverified 仅设置返回检测——没有"等 N 天"路径
        XCTAssertEqual(AgeGateMatrix.cell(state: .ageUnresolved, variant: .release).autoExit, .retryUntilResolved)
        XCTAssertEqual(AgeGateMatrix.cell(state: .unverified, variant: .release).autoExit, .onDidBecomeActive)
    }

    /// 不变式 5/6：状态条与拦截页同源——curtain 标题必须以 banner 文本开头（引用而非另写）。
    func testCurtainTitleDerivesFromBanner() {
        for state in [AgeGateState.minorConfirmed, .ageUnresolved] {
            for variant in BuildVariant.allCases {
                guard let banner = AgeGateMatrix.bannerText(state: state, variant: variant) else { continue }
                for curtain in AgeGateMatrix.curtainVariants(state: state, variant: variant) {
                    XCTAssertTrue(curtain.title.hasPrefix(banner),
                        "\(state)/\(variant) 拦截页标题未引用状态条文案：\(curtain.title)")
                }
            }
        }
    }

    /// 拦截页条目数 2／1／0（AGE_MATRIX §1 拦截页键列）。
    func testCurtainVariantCounts() {
        for variant in BuildVariant.allCases {
            XCTAssertEqual(AgeGateMatrix.curtainVariants(state: .minorConfirmed, variant: variant).count, 2)
            XCTAssertEqual(AgeGateMatrix.curtainVariants(state: .ageUnresolved, variant: variant).count, 1)
            XCTAssertEqual(AgeGateMatrix.curtainVariants(state: .unverified, variant: variant).count, 0)
            XCTAssertEqual(AgeGateMatrix.curtainVariants(state: .adultConfirmed, variant: variant).count, 0)
        }
    }

    /// 文案禁词（禁词表 §3 未成年人模式专项 + 自加的"联网"）：退出/解锁/切换/跳过/联网。
    func testNoBypassWordingInProtectedCopy() {
        let banned = ["退出", "解锁", "切换模式", "跳过", "联网", "破解"]
        for state in [AgeGateState.minorConfirmed, .ageUnresolved, .unverified] {
            for variant in BuildVariant.allCases {
                if let banner = AgeGateMatrix.bannerText(state: state, variant: variant) {
                    for word in banned {
                        XCTAssertFalse(banner.contains(word), "\(state)/\(variant) 状态条含禁词「\(word)」：\(banner)")
                    }
                }
                for curtain in AgeGateMatrix.curtainVariants(state: state, variant: variant) {
                    for word in banned {
                        XCTAssertFalse(curtain.title.contains(word), "\(state) 拦截页标题含禁词「\(word)」")
                        XCTAssertFalse(curtain.caption.contains(word), "\(state) 拦截页副文案含禁词「\(word)」")
                    }
                }
            }
        }
    }

    /// D-03：时长上限 TBD——矩阵与文案不得出现任何分钟数。
    func testQuotaCopyContainsNoNumbers() {
        for curtain in AgeGateMatrix.curtainVariants(state: .minorConfirmed, variant: .release) {
            // 副文案"次日自动恢复"无数字；"每日 22:00–6:00"是宵禁时段（时刻不是额度），
            // D-03 禁的是时长额度数字——放行时刻表、拦截额度数。
            XCTAssertFalse(curtain.caption.contains("分钟"), "时长额度不得出现分钟数：\(curtain.caption)")
            XCTAssertFalse(curtain.title.contains("分钟"), "时长额度不得出现分钟数")
        }
        XCTAssertNil(DailyReadingQuota.minutesTBD, "D-03：额度数值保持 TBD")
    }
}
