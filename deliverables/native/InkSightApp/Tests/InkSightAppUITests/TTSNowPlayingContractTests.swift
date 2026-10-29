import XCTest
@testable import InkSightAppUI
@testable import InkSightAppKit
import Foundation

/// FR-012「锁屏可控」契约测试（D-93 遗留补齐项）。
final class TTSNowPlayingContractTests: XCTestCase {

    private func source(_ module: String, _ name: String) throws -> String {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/\(module)")
        let raw = try String(contentsOf: base.appendingPathComponent(name), encoding: .utf8)
        return raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return !t.hasPrefix("//") && !t.hasPrefix("///") && !t.hasPrefix("*")
            }.joined(separator: "\n")
    }

    /// 注册了 play/pause/togglePlayPause 三个遥控命令。
    func testRemoteCommandsRegistered() throws {
        let src = try source("InkSightAppKit", "TTSNowPlayingBridge.swift")
        XCTAssertTrue(src.contains("MPRemoteCommandCenter"), "须用遥控中心")
        XCTAssertTrue(src.contains("playCommand"), "须注册播放命令")
        XCTAssertTrue(src.contains("pauseCommand"), "须注册暂停命令")
        XCTAssertTrue(src.contains("togglePlayPauseCommand"), "须注册切换命令")
    }

    /// **不注册 next/previous**（单章朗读，无"下一首"概念）。
    ///
    /// 注册一个点了没反应或跳错的按钮比不注册更糟。
    func testDoesNotRegisterNextPrevious() throws {
        let src = try source("InkSightAppKit", "TTSNowPlayingBridge.swift")
        XCTAssertTrue(src.contains("nextTrackCommand.isEnabled = false"),
                      "nextTrack 须显式禁用")
        XCTAssertTrue(src.contains("previousTrackCommand.isEnabled = false"),
                      "previousTrack 须显式禁用")
    }

    /// 维护 Now Playing 信息（锁屏显示"在朗读什么"）。
    func testNowPlayingInfoMaintained() throws {
        let src = try source("InkSightAppKit", "TTSNowPlayingBridge.swift")
        XCTAssertTrue(src.contains("MPNowPlayingInfoCenter"), "须维护 Now Playing")
        XCTAssertTrue(src.contains("MPMediaItemPropertyTitle"), "须设标题")
        XCTAssertTrue(src.contains("MPMediaItemPropertyArtist"), "须设章节")
    }

    /// **不伪造时长**（TTS 无预知时长，假的进度条比例更糟）。
    func testDoesNotFakeDuration() throws {
        let src = try source("InkSightAppKit", "TTSNowPlayingBridge.swift")
        XCTAssertFalse(src.contains("MPMediaItemPropertyPlaybackDuration:"),
                       "不得设置假的播放时长")
    }

    /// **音频会话真被调用**（D-93 登记为"未被调用"的缺口）。
    func testAudioSessionIsActivated() throws {
        let src = try source("InkSightAppKit", "TTSNowPlayingBridge.swift")
        XCTAssertTrue(src.contains("activatePlaybackCategory()"),
                      "须激活音频会话（锁屏后台播放前提）")
        XCTAssertTrue(src.contains("TTSAudioSession.deactivate()"),
                      "结束时须释放会话")
    }

    /// 阅读器接了桥：开始朗读时 begin、退出时 end。
    func testReaderWiresBridge() throws {
        let src = try source("InkSightAppUI", "ReaderSurface.swift")
        XCTAssertTrue(src.contains("nowPlaying.begin("), "开始朗读须接桥")
        XCTAssertTrue(src.contains("nowPlaying.end()"), "退出须释放桥")
    }
}
