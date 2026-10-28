import XCTest
@testable import InkSightAppKit
import CoreGraphics

/// EGG4 页角折角双判定契约测试（DESIGN §5 ④ 规范正文）。
final class DogEarGestureResolverTests: XCTestCase {

    private let container = CGSize(width: 393, height: 852)

    /// 常量与规范一致：44pt 热区 / 300ms / 12pt。
    func testConstants() {
        XCTAssertEqual(DogEarGestureResolver.hotZoneSize, 44)
        XCTAssertEqual(DogEarGestureResolver.holdThresholdSeconds, 0.300)
        XCTAssertEqual(DogEarGestureResolver.snapThresholdPoints, 12)
    }

    /// 右下角 44×44 热区判定。
    func testHotZoneIsBottomRight44() {
        // 右下角内
        XCTAssertTrue(DogEarGestureResolver.isInHotZone(
            CGPoint(x: 393 - 10, y: 852 - 10), containerSize: container))
        // 热区边界（左上角那一点）
        XCTAssertTrue(DogEarGestureResolver.isInHotZone(
            CGPoint(x: 393 - 44, y: 852 - 44), containerSize: container))
        // 热区外（向左 1pt）
        XCTAssertFalse(DogEarGestureResolver.isInHotZone(
            CGPoint(x: 393 - 45, y: 852 - 10), containerSize: container))
        // 热区外（向上 1pt）
        XCTAssertFalse(DogEarGestureResolver.isInHotZone(
            CGPoint(x: 393 - 10, y: 852 - 45), containerSize: container))
        // 左上角肯定不在
        XCTAssertFalse(DogEarGestureResolver.isInHotZone(
            CGPoint(x: 10, y: 10), containerSize: container))
    }

    /// **<300ms 抬手 → 翻页**（该角不留死区）。
    func testShortPressTurnsPage() {
        XCTAssertEqual(DogEarGestureResolver.resolveTap(pressDuration: 0.1), .pageTurn)
        XCTAssertEqual(DogEarGestureResolver.resolveTap(pressDuration: 0.299), .pageTurn)
        XCTAssertFalse(DogEarGestureResolver.resolveTap(pressDuration: 0.1).writesBookmark)
        XCTAssertEqual(DogEarGestureResolver.resolveTap(pressDuration: 0.1).hapticCount, 0,
                       "短按翻页不应有触感")
    }

    /// **≥300ms → 进入折角跟手**（一次 .light）。
    func testLongPressEntersDogEar() {
        XCTAssertEqual(DogEarGestureResolver.resolveTap(pressDuration: 0.300), .enterDogEar)
        XCTAssertEqual(DogEarGestureResolver.resolveTap(pressDuration: 1.5), .enterDogEar)
        XCTAssertEqual(DogEarGestureResolver.resolveTap(pressDuration: 0.5).hapticCount, 1,
                       "进入折角应有一次触感")
        XCTAssertFalse(DogEarGestureResolver.resolveTap(pressDuration: 0.5).writesBookmark)
    }

    /// **松手 >12pt → 吸附并写书签**（再一次 .light，共 2 次）。
    func testReleaseBeyondThresholdSnapsAndBookmarks() {
        let outcome = DogEarGestureResolver.resolveRelease(verticalTranslation: 13)
        XCTAssertEqual(outcome, .snapAndBookmark)
        XCTAssertTrue(outcome.writesBookmark, "吸附必须写书签")
        XCTAssertEqual(outcome.hapticCount, 2, "进入 1 次 + 书签 1 次")
    }

    /// **松手 ≤12pt → 回弹，不写书签**。
    func testReleaseWithinThresholdSpringsBack() {
        for translation in [CGFloat(0), 6, 12] {
            let outcome = DogEarGestureResolver.resolveRelease(verticalTranslation: translation)
            XCTAssertEqual(outcome, .springBack, "位移 \(translation)pt 应回弹")
            XCTAssertFalse(outcome.writesBookmark, "回弹不得写书签")
            XCTAssertEqual(outcome.hapticCount, 1, "只有进入时那一次触感")
        }
    }

    /// 边界值 12pt 本身属于回弹（规范写「>12pt」）。
    func testSnapBoundaryIsExclusive() {
        XCTAssertEqual(DogEarGestureResolver.resolveRelease(verticalTranslation: 12), .springBack)
        XCTAssertEqual(DogEarGestureResolver.resolveRelease(verticalTranslation: 12.01),
                       .snapAndBookmark)
    }

    /// 关闭态等价路径：EGG4 不注册时**加书签走工具条**（功能不丢）。
    /// 本测试确认写入书签的判定只有一个来源，避免两处口径分叉。
    func testBookmarkWriteHasSingleSource() {
        // 只有 snapAndBookmark 写书签；其余三种都不写
        let all: [DogEarGestureResolver.Outcome] = [.pageTurn, .enterDogEar, .springBack]
        for outcome in all {
            XCTAssertFalse(outcome.writesBookmark, "\(outcome) 不得写书签")
        }
        XCTAssertTrue(DogEarGestureResolver.Outcome.snapAndBookmark.writesBookmark)
    }
}
