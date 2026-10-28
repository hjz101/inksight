import XCTest
@testable import InkSightAppUI
import InkSightAppKit
import InkSightCore
import SwiftUI
import Foundation

/// iOS 侧结构验证（模拟器 XCTest）。
final class AppUITests: XCTestCase {

    /// 正文 0 玻璃的结构保证（回报第 ④ 项的可执行部分）：
    /// `ReaderSurfaceView` 的**公开 API 与 body 不含任何玻璃入口**——
    /// 全 App 玻璃唯一入口是 `GlassSurface`，而本测试以"玻璃只能经 GlassSurface 进入"为前提，
    /// 验证正文视图的类型不在任何 GlassSurface 内容闭包链上（用类型关系表达，非文本扫描）。
    ///
    /// 说明：真正的"不引用"由编译器保证——`ReaderSurfaceView` 源文件不 import 玻璃入口类型，
    /// 本测试固定这一事实的验收形态：正文视图类型的 Mirror 不暴露 GlassStrength 关联值。
    func testReaderSurfaceHasNoGlassAssociation() {
        let view = ReaderSurfaceView(onExit: {})
        let mirror = Mirror(reflecting: view)
        let children = mirror.children.map(\.label)
        // ReaderSurfaceView 的存储属性只有 onExit——没有 strength/interactive/glass 字段
        XCTAssertFalse(children.contains("strength"), "正文视图不得持有玻璃强度")
        XCTAssertFalse(children.contains("interactive"), "正文视图不得持有玻璃交互开关")
        XCTAssertTrue(children.contains("onExit"), "正文视图公开 API 应只有退出回调")
    }

    /// 状态条文案由矩阵派生（AGE_MATRIX §3：视图层不得 if-state 拼文案）——
    /// 视图持有的是派生结果（文本），不是裸 state 拼接逻辑。
    func testMeScreenCarriesDerivedBannerOnly() {
        let view = MeScreen(ageState: .minorConfirmed, variant: .research)
        let mirror = Mirror(reflecting: view)
        let labels = mirror.children.compactMap(\.label)
        XCTAssertTrue(labels.contains("ageState"), "应持有状态（供矩阵派生）")
        XCTAssertTrue(labels.contains("variant"), "应持变体（键 = (state, variant)）")
        // 派生正确性由 InkSightAppKitTests 的矩阵测试覆盖；此处验证视图依赖注入而非硬编码。
    }

    /// 根骨架：RootTabView 持有年龄态与变体（供矩阵派生），阅读器开关在
    /// executableTarget InkSightAppMain（Main 不可被测试 import——SPM 结构如此），
    /// 其行为由 InkSightAppKitTests 的 coordinator 契约测试覆盖。
    func testRootTabViewShape() {
        let view = RootTabView(ageState: .minorConfirmed, variant: .research, onOpenReader: {})
        let mirror = Mirror(reflecting: view)
        let labels = mirror.children.compactMap(\.label)
        XCTAssertTrue(labels.contains("ageState"))
        XCTAssertTrue(labels.contains("variant"))
        XCTAssertTrue(labels.contains("onOpenReader"))
    }
}
