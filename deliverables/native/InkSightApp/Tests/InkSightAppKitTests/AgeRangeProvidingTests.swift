import XCTest
@testable import InkSightAppKit

/// FR-032 DeclaredAgeRange 注入点与四态派生契约测试。
final class AgeRangeProvidingTests: XCTestCase {

    /// **拒绝共享 → `.unverified`**（不是放行）。
    func testDeclinedMapsToUnverified() {
        XCTAssertEqual(AgeGateState.from(.declined), .unverified,
                       "拒答必须保守为 unverified，不得 default 放行")
    }

    /// **系统不可用 → `.unverified`**（不假定成年）。
    func testUnavailableMapsToUnverified() {
        XCTAssertEqual(AgeGateState.from(.unavailable), .unverified,
                       "系统不可用同样保守，不假定成年")
    }

    /// 明确成年（下界 ≥18 且无上界）→ `.adultConfirmed`。
    func testAdultConfirmed() {
        XCTAssertEqual(AgeGateState.from(.sharing(lowerBound: 18, upperBound: nil)), .adultConfirmed)
        XCTAssertEqual(AgeGateState.from(.sharing(lowerBound: 25, upperBound: nil)), .adultConfirmed)
        XCTAssertEqual(AgeGateState.from(.sharing(lowerBound: 18, upperBound: 65)), .adultConfirmed)
    }

    /// 明确未成年（上界 ≤17）→ `.minorConfirmed`。
    func testMinorConfirmed() {
        XCTAssertEqual(AgeGateState.from(.sharing(lowerBound: 13, upperBound: 17)), .minorConfirmed)
        XCTAssertEqual(AgeGateState.from(.sharing(lowerBound: 0, upperBound: 12)), .minorConfirmed)
    }

    /// **跨 18 边界不可断定 → `.ageUnresolved`**（套宵禁，保守）。
    func testCrossingBoundaryIsUnresolved() {
        XCTAssertEqual(AgeGateState.from(.sharing(lowerBound: 16, upperBound: 20)), .ageUnresolved,
                       "跨 18 边界不可断定，须为 ageUnresolved")
        XCTAssertEqual(AgeGateState.from(.sharing(lowerBound: 13, upperBound: 18)), .ageUnresolved)
    }

    /// 下界 <18 且无上界 → 不可断定。
    func testLowerBoundBelowAdultIsUnresolved() {
        XCTAssertEqual(AgeGateState.from(.sharing(lowerBound: 13, upperBound: nil)), .ageUnresolved)
    }

    /// **无 `default: 放行`**：四种输入映射到四态，且拒答/不可用都不落到成年态。
    func testNoDefaultAllow() {
        let cases: [AgeRangeDeclaration] = [
            .declined, .unavailable,
            .sharing(lowerBound: 18, upperBound: nil),
            .sharing(lowerBound: 13, upperBound: 17),
            .sharing(lowerBound: 16, upperBound: 20),
        ]
        for decl in cases {
            let state = AgeGateState.from(decl)
            XCTAssertTrue(AgeGateState.allCases.contains(state), "必须映射到合法四态之一")
        }
        // 保守性：declined / unavailable 绝不能是 adultConfirmed
        XCTAssertNotEqual(AgeGateState.from(.declined), .adultConfirmed)
        XCTAssertNotEqual(AgeGateState.from(.unavailable), .adultConfirmed)
    }

    /// 系统实现的 gate 常量 = 18（最小必要，只申请 1 个）。
    func testRequestedGateIs18() {
        XCTAssertEqual(SystemDeclaredAgeRangeProvider.requestedGate, 18,
                       "FR-032：只申请 1 个 gate=18")
    }

    /// 系统实现在当前 SDK 下诚实返回 unavailable（不伪装成共享）。
    func testSystemProviderIsHonestWhenUnavailable() async {
        let result = await SystemDeclaredAgeRangeProvider().requestAgeRange()
        // 当前 SDK 无 AgeRangeService：应诚实返回 unavailable（保守 → unverified）
        XCTAssertEqual(result, .unavailable, "不可用时必须如实返回，不伪造共享结果")
        XCTAssertEqual(AgeGateState.from(result), .unverified)
    }

    /// Mock 注入可用于测试/演示。
    func testMockProvider() async {
        let mock = MockAgeRangeProvider(.sharing(lowerBound: 13, upperBound: 17))
        let result = await mock.requestAgeRange()
        XCTAssertEqual(AgeGateState.from(result), .minorConfirmed)
    }
}
