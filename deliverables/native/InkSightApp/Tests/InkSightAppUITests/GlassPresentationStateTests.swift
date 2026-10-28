import XCTest
@testable import InkSightAppUI
import SwiftUI

/// FR-014 玻璃四态收起契约测试（DESIGN §2.5）。
final class GlassPresentationStateTests: XCTestCase {

    /// 四态齐备（P0 验收项：静止 / 滚动中 / 转场 / 手势跟手）。
    func testFourStatesExist() {
        let all: [GlassPresentationState] = [.steady, .scrolling, .transition, .gesture]
        XCTAssertEqual(all.count, 4, "DESIGN §2.5 定义四态")
    }

    /// 稳态与转场用完整玻璃；滚动/手势降级为纯色。
    func testGlassVsFallback() {
        XCTAssertTrue(GlassPresentationState.steady.usesGlass)
        XCTAssertFalse(GlassPresentationState.steady.usesOpaqueFallback)

        // 转场：**材质冻结**——仍用玻璃，不插值材质参数（只允许 opacity/transform）
        XCTAssertTrue(GlassPresentationState.transition.usesGlass,
                      "转场期间材质冻结，仍为玻璃")
        XCTAssertFalse(GlassPresentationState.transition.usesOpaqueFallback)

        // 滚动 / 手势：降级纯色 + 1pt 描边
        XCTAssertTrue(GlassPresentationState.scrolling.usesOpaqueFallback)
        XCTAssertFalse(GlassPresentationState.scrolling.usesGlass)
        XCTAssertTrue(GlassPresentationState.gesture.usesOpaqueFallback)
        XCTAssertFalse(GlassPresentationState.gesture.usesGlass)
    }

    /// 每种状态只能是「玻璃」或「降级」之一，不可兼得、不可都不选。
    func testStatesAreMutuallyExclusive() {
        for state in [GlassPresentationState.steady, .scrolling, .transition, .gesture] {
            XCTAssertNotEqual(state.usesGlass, state.usesOpaqueFallback,
                              "\(state) 必须且只能二选一")
        }
    }

    /// 时长常量（DESIGN §2.5：恢复 120ms、转场 380ms）。
    func testDurations() {
        XCTAssertEqual(GlassPresentationState.restoreDuration, 0.12, "结束后 120ms 淡回")
        XCTAssertEqual(GlassPresentationState.transitionDuration, 0.38, "转场 380ms")
    }
}
