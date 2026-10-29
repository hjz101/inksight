import Foundation
#if canImport(MediaPlayer)
import MediaPlayer
#endif
#if os(iOS) && canImport(AVFoundation)
import AVFoundation
#endif

// MARK: - TTSNowPlayingBridge（FR-012 锁屏可控）

/// 锁屏/控制中心遥控桥（FR-012「锁屏可控」的落地）。
///
/// 职责（D-93 遗留的补齐）：
/// - 注册 `MPRemoteCommandCenter` 的 **play / pause / togglePlayPause** 命令，
///   转发给 `TTSEngine`；
/// - 维护 `MPNowPlayingInfoCenter` 的标题/章节/进度，让锁屏显示"正在朗读什么"；
/// - **激活音频会话**（`.playback` ＋ `.spokenAudio`）使后台播放成立
///   —— 这是锁屏可控的前提，之前 `TTSAudioSession` 一直没人调用。
///
/// 平台：`MediaPlayer` 仅 iOS 有；macOS 测试构建下整段条件编译掉，
/// 保证「同一份源码两平台都能编译」。
@MainActor
public final class TTSNowPlayingBridge {

    /// 供 `TTSEngine` 回调（播放/暂停/停止）。
    public struct Handlers {
        public var play: () -> Void
        public var pause: () -> Void
        public var stop: () -> Void

        public init(play: @escaping () -> Void,
                    pause: @escaping () -> Void,
                    stop: @escaping () -> Void) {
            self.play = play
            self.pause = pause
            self.stop = stop
        }
    }

    private var handlers: Handlers?
    private var registered = false

    public init() {}

    /// 开始朗读前调用：激活音频会话 ＋ 注册遥控命令 ＋ 设初始 Now Playing。
    ///
    /// - Parameters:
    ///   - title: 书名（锁屏显示）。
    ///   - chapterTitle: 章节名。
    ///   - handlers: 遥控回调。
    public func begin(title: String, chapterTitle: String, handlers: Handlers) {
        self.handlers = handlers
        activateSessionIfPossible()
        registerCommandsIfNeeded()
        updateNowPlaying(title: title, chapterTitle: chapterTitle,
                         elapsed: 0, isPlaying: true)
    }

    /// 停止朗读后调用：清空 Now Playing ＋ 注销命令 ＋ 释放音频会话。
    public func end() {
        handlers = nil
        unregisterCommands()
        #if canImport(MediaPlayer)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #endif
        #if os(iOS) && canImport(AVFoundation)
        TTSAudioSession.deactivate()
        #endif
    }

    /// 更新锁屏进度（朗读推进/暂停时调用）。
    public func updateNowPlaying(title: String, chapterTitle: String,
                                 elapsed: TimeInterval, isPlaying: Bool) {
        #if canImport(MediaPlayer)
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: chapterTitle,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        // 时长未知（TTS 无预知时长）→ 不设 MPMediaItemPropertyPlaybackDuration，
        // **不伪造一个假的时长**（会让锁屏进度条显示错误比例）。
        info[MPMediaItemPropertyMediaType] = MPMediaType.audioBook.rawValue
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #endif
    }

    // MARK: - 内部

    private func activateSessionIfPossible() {
        #if os(iOS) && canImport(AVFoundation)
        // 锁屏后台播放的前提：`.playback` 类别 + 激活。
        try? TTSAudioSession.activatePlaybackCategory()
        #endif
    }

    #if canImport(MediaPlayer)
    private func registerCommandsIfNeeded() {
        guard !registered else { return }
        registered = true
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.handlers?.play() }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.handlers?.pause() }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            // 切换语义由引擎侧决定（它知道当前是 speaking 还是 paused）
            Task { @MainActor in self.handlers?.play() }
            return .success
        }

        // 明确**不注册** next/previous（单章朗读，无"下一首"概念——
        // 注册一个点了没反应或跳错的按钮比不注册更糟）。
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
    }

    private func unregisterCommands() {
        guard registered else { return }
        registered = false
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
    }
    #else
    private func registerCommandsIfNeeded() {}
    private func unregisterCommands() {}
    #endif
}
