import XCTest
@testable import InkSightAppKit

/// FR-024a 检索结果 → 阅读器跳转路由测试。
final class ReaderNavigatorTests: XCTestCase {

    func testRequestThenConsumeIsOneShot() {
        let navigator = ReaderNavigator()
        let request = ReaderNavigationRequest(bookID: "b1", chapterIndex: 3, charOffset: 42)
        XCTAssertFalse(navigator.hasPending)
        navigator.request(request)
        XCTAssertTrue(navigator.hasPending)
        XCTAssertEqual(navigator.consume(), request)
        XCTAssertFalse(navigator.hasPending)
        XCTAssertNil(navigator.consume(), "请求必须一次性消费，避免重复打开")
    }

    func testLatestRequestReplacesPending() {
        let navigator = ReaderNavigator()
        navigator.request(ReaderNavigationRequest(bookID: "old", chapterIndex: 0))
        let latest = ReaderNavigationRequest(bookID: "new", chapterIndex: 2, charOffset: 99)
        navigator.request(latest)
        XCTAssertEqual(navigator.consume(), latest, "后到的导航意图应覆盖旧请求")
    }

    func testSharedIsStableAndExplicitInstancesAreIsolated() {
        XCTAssertTrue(ReaderNavigator.shared === ReaderNavigator.shared)
        let isolated = ReaderNavigator()
        isolated.request(ReaderNavigationRequest(bookID: "isolated", chapterIndex: 1))
        XCTAssertTrue(isolated.hasPending)
        XCTAssertFalse(ReaderNavigator.shared.hasPending)
    }
}
