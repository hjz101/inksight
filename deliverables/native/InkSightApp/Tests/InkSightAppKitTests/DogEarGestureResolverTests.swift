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

/// EGG4 短按翻页分支的接线契约（`DragGesture` + 延时任务组合）。
final class DogEarShortPressWiringTests: XCTestCase {

    private func readerSource() throws -> String {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/InkSightAppUI")
        let raw = try String(contentsOf: base.appendingPathComponent("ReaderSurface.swift"),
                             encoding: .utf8)
        return raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return !t.hasPrefix("//") && !t.hasPrefix("///") && !t.hasPrefix("*")
            }
            .joined(separator: "\n")
    }

    /// 短按分支已接线（`advancePageInDogEarZone`）。
    func testShortPressAdvancesPage() throws {
        let src = try readerSource()
        XCTAssertTrue(src.contains("advancePageInDogEarZone"),
                      "短按抬手须走翻页分支（该角不留死区）")
    }

    /// 用延时任务区分长按/短按（`DragGesture` 无法单独区分）。
    func testUsesHoldDelayTask() throws {
        let src = try readerSource()
        XCTAssertTrue(src.contains("dogEarHoldTask"),
                      "须用延时任务在 300ms 处判定长按")
        XCTAssertTrue(src.contains("Task.sleep"), "须有 300ms 延时")
        XCTAssertTrue(src.contains(".cancel()"), "抬手须取消延时任务")
    }

    /// 翻页在页边界收敛（末页不越界）。
    func testPageAdvanceClampsAtBoundary() throws {
        let src = try readerSource()
        guard let range = src.range(of: "private func advancePageInDogEarZone") else {
            return XCTFail("找不到 advancePageInDogEarZone")
        }
        let body = String(src[range.lowerBound...].prefix(400))
        XCTAssertTrue(body.contains("min("), "前进须做上界收敛")
        XCTAssertTrue(body.contains("pageCount"), "须以 pageCount 为界")
    }

    /// 阈值采纳 300ms（DESIGN 双判定正文），且**冲突已在源码登记**。
    func testThresholdAdoptedIsDesignSide() {
        XCTAssertEqual(DogEarGestureResolver.holdThresholdSeconds, 0.300,
                       "采纳 DESIGN 的 300ms（双判定正文）")
    }
}
