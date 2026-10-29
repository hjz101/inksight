import XCTest
@testable import InkSightAppUI
import Foundation

/// FR-012 续章契约（章末自动加载下一章连续朗读）。
final class TTSAutoContinueTests: XCTestCase {

    private func source(_ name: String) throws -> String {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/InkSightAppUI")
        let raw = try String(contentsOf: base.appendingPathComponent(name), encoding: .utf8)
        return raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return !t.hasPrefix("//") && !t.hasPrefix("///") && !t.hasPrefix("*")
            }.joined(separator: "\n")
    }

    /// 挂了 `onFinishedChapter` 回调。
    func testFinishedCallbackWired() throws {
        let src = try source("ReaderSurface.swift")
        XCTAssertTrue(src.contains("tts.onFinishedChapter"), "须挂章末回调")
        XCTAssertTrue(src.contains("continueReadingNextChapter"), "须有续章方法")
    }

    /// **末章停止，不循环**（循环会让用户以为"读不完"）。
    func testStopsAtLastChapter() throws {
        let src = try source("ReaderSurface.swift")
        guard let range = src.range(of: "private func continueReadingNextChapter") else {
            return XCTFail("找不到续章方法")
        }
        let body = String(src[range.lowerBound...].prefix(900))
        XCTAssertTrue(body.contains("next < item.chapters.count"), "须判断是否末章")
        XCTAssertTrue(body.contains("tts.stop()"), "末章须停止")
        XCTAssertTrue(body.contains("已读完本书") || body.contains("读完"), "末章须有反馈")
    }

    /// 续章后**重新接 Now Playing**（章节名变了，锁屏要同步）。
    func testRefreshesNowPlayingAfterContinue() throws {
        let src = try source("ReaderSurface.swift")
        guard let range = src.range(of: "private func continueReadingNextChapter") else {
            return XCTFail("找不到续章方法")
        }
        let body = String(src[range.lowerBound...].prefix(900))
        XCTAssertTrue(body.contains("nowPlaying.updateNowPlaying"),
                      "续章后须更新锁屏章节名")
    }

    /// 续章走与目录跳转同一路径（行为一致）。
    func testUsesSameJumpPathAsTOC() throws {
        let src = try source("ReaderSurface.swift")
        guard let range = src.range(of: "private func continueReadingNextChapter") else {
            return XCTFail("找不到续章方法")
        }
        let body = String(src[range.lowerBound...].prefix(900))
        XCTAssertTrue(body.contains("jumpToChapter(next)"),
                      "续章应复用目录跳转路径（行为一致）")
    }

    /// 有开关可关闭续章。
    func testAutoContinueCanBeDisabled() throws {
        let src = try source("ReaderSurface.swift")
        XCTAssertTrue(src.contains("ttsAutoContinue"), "须有续章开关")
    }
}
