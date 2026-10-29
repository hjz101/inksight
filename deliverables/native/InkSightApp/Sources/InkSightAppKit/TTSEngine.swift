import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

// MARK: - TTSState（FR-012 TTS 朗读状态）

/// TTS 朗读状态（纯逻辑，可测）。
public enum TTSPlaybackState: Equatable, Sendable {
    case idle
    case speaking
    case paused

    public var isActive: Bool { self != .idle }
}

// MARK: - TTSSettings（FR-012 朗读参数）

/// 朗读设置（FR-012：**0.5–2.5 倍速**、定时关闭）。
public struct TTSSettings: Codable, Equatable, Sendable {
    /// 语速倍数（FR-012 原文范围 0.5–2.5）。
    public var rateMultiplier: Double
    /// 定时关闭（分钟；nil ＝ 不自动停）。
    public var sleepTimerMinutes: Int?

    /// 语速合法范围（FR-012 原文）。
    public static let minRate: Double = 0.5
    public static let maxRate: Double = 2.5
    /// 默认语速（系统正常速度）。
    public static let defaultRate: Double = 1.0
    /// 定时关闭可选档（分钟）。
    public static let sleepTimerOptions: [Int] = [15, 30, 60]

    public init(rateMultiplier: Double = TTSSettings.defaultRate,
                sleepTimerMinutes: Int? = nil) {
        self.rateMultiplier = rateMultiplier
        self.sleepTimerMinutes = sleepTimerMinutes
    }

    /// 归一化语速到合法区间（越界值夹取，不是静默忽略）。
    public var clampedRate: Double {
        min(max(rateMultiplier, TTSSettings.minRate), TTSSettings.maxRate)
    }

    /// 归一化（写入前调用，防越界值落盘）。
    public func normalized() -> TTSSettings {
        var copy = self
        copy.rateMultiplier = clampedRate
        return copy
    }
}

// MARK: - TTSEngine（FR-012 朗读引擎，AVFoundation 适配）

/// TTS 朗读引擎（FR-012：系统语音、0.5–2.5 倍速、定时关闭、锁屏可控）。
///
/// **平台策略**：
/// - iOS 用 `AVSpeechSynthesizer`（系统语音，无需第三方）；
/// - macOS 测试构建同样有 AVFoundation，故 `#if canImport(AVFoundation)` 两平台通用；
/// - **锁屏可控**由系统 `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter` 提供，
///   需在 App 层激活 `AVAudioSession` 类别（`.playback`）——本引擎提供状态与回调，
///   会话配置属宿主职责（见 `activateAudioSessionIfNeeded`）。
///
/// **合规**：TTS 只朗读**当前会话内存中的章节文本**（≤3 章约束不变），
/// 不落盘、不产生网络请求（离线系统语音）。
@MainActor
public final class TTSEngine: NSObject, ObservableObject {

    @Published public private(set) var state: TTSPlaybackState = .idle
    /// 当前朗读到的字符偏移（用于进度显示与续读）。
    @Published public private(set) var currentCharOffset: Int = 0
    @Published public var settings: TTSSettings

    #if canImport(AVFoundation)
    private let synthesizer = AVSpeechSynthesizer()
    #endif
    private var sleepTask: Task<Void, Never>?
    /// 分段朗读的回调（每段读完推进 offset）。
    private var segments: [(offset: Int, text: String)] = []
    private var segmentIndex = 0

    /// 朗读结束回调（供 UI/上层推进章节；nil ＝ 不通知）。
    public var onFinishedChapter: (() -> Void)?

    public override init() {
        self.settings = TTSSettings()
        super.init()
        #if canImport(AVFoundation)
        synthesizer.delegate = self
        #endif
    }

    public init(settings: TTSSettings) {
        self.settings = settings.normalized()
        super.init()
        #if canImport(AVFoundation)
        synthesizer.delegate = self
        #endif
    }

    /// 开始朗读整章（分段：按段落切，逐段推进 offset）。
    ///
    /// - Parameters:
    ///   - text: 章节纯文本（**已在会话内存中**，不额外读盘）。
    ///   - startingOffset: 起始字符偏移（续读）。
    public func start(text: String, startingOffset: Int = 0) {
        stop()
        segments = Self.segment(text, from: startingOffset)
        guard !segments.isEmpty else { return }
        segmentIndex = 0
        currentCharOffset = segments[0].offset
        state = .speaking
        speakCurrentSegment()
        scheduleeSleepTimerIfNeeded()
    }

    /// 暂停/继续。
    public func pause() {
        guard state == .speaking else { return }
        #if canImport(AVFoundation)
        synthesizer.pauseSpeaking(at: .word)
        #endif
        state = .paused
    }

    public func resume() {
        guard state == .paused else { return }
        #if canImport(AVFoundation)
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
        } else {
            speakCurrentSegment()
        }
        #endif
        state = .speaking
    }

    /// 停止（释放朗读器与定时器）。
    public func stop() {
        #if canImport(AVFoundation)
        synthesizer.stopSpeaking(at: .immediate)
        #endif
        sleepTask?.cancel()
        sleepTask = nil
        segments = []
        segmentIndex = 0
        state = .idle
    }

    /// 调整语速（运行中立即生效：重设当前段语音）。
    public func updateRate(_ rate: Double) {
        settings.rateMultiplier = min(max(rate, TTSSettings.minRate), TTSSettings.maxRate)
        if state == .speaking { speakCurrentSegment() }
    }

    /// 设置定时关闭（分钟；nil ＝ 取消）。
    public func setSleepTimer(minutes: Int?) {
        settings.sleepTimerMinutes = minutes
        sleepTask?.cancel()
        sleepTask = nil
        if state == .speaking { scheduleeSleepTimerIfNeeded() }
    }

    // MARK: - 内部

    private func scheduleeSleepTimerIfNeeded() {
        guard let minutes = settings.sleepTimerMinutes, minutes > 0 else { return }
        sleepTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Double(minutes) * 60))
            guard !Task.isCancelled else { return }
            self.stop()
        }
    }

    /// 朗读当前段（**不自增 index**——推进由 delegate 的 `didFinish` 驱动）。
    private func speakCurrentSegment() {
        guard segmentIndex < segments.count else {
            stop()
            onFinishedChapter?()
            return
        }
        let seg = segments[segmentIndex]
        currentCharOffset = seg.offset
        #if canImport(AVFoundation)
        let utterance = AVSpeechUtterance(string: seg.text)
        utterance.rate = Self.avRate(for: settings.clampedRate)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        synthesizer.speak(utterance)
        #endif
    }

    /// 分段：按段落边界切（每段最多 400 字，避免超长 utterance）。
    nonisolated static func segment(_ text: String, from offset: Int) -> [(offset: Int, text: String)] {
        let ns = text as NSString
        guard offset >= 0, offset < ns.length else { return [] }
        var result: [(Int, String)] = []
        var cursor = offset
        let maxLen = 400
        while cursor < ns.length {
            let remaining = ns.length - cursor
            let len = min(maxLen, remaining)
            let chunk = ns.substring(with: NSRange(location: cursor, length: len))
            result.append((cursor, chunk))
            cursor += len
        }
        return result
    }

    /// 语速倍数 → AVSpeechUtterance.rate（系统范围 0…1，默认 ~0.5）。
    nonisolated static func avRate(for multiplier: Double) -> Float {
        // 经验映射：1.0 倍 ≈ 0.5（系统默认）；0.5 倍 ≈ 0.25；2.5 倍 ≈ 0.9
        Float(min(max(multiplier * 0.5, 0.1), 1.0))
    }
}

// MARK: - 音频会话（锁屏可控的前提）

public enum TTSAudioSession {
    /// 激活 `.playback` 类别（锁屏后台播放 + 控制中心可控的前提）。
    ///
    /// **由宿主在开始朗读前调用**（App 层职责；引擎不擅自改全局音频会话）。
    #if os(iOS) && canImport(AVFoundation)
    public static func activatePlaybackCategory() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio,
                                options: [.duckOthers])
        try session.setActive(true)
    }

    public static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false,
                                                     options: [.notifyOthersOnDeactivation])
    }
    #endif
}

// MARK: - AVSpeechSynthesizerDelegate（逐段推进）

#if canImport(AVFoundation)
extension TTSEngine: AVSpeechSynthesizerDelegate {

    /// 一段读完 → 推进到下一段并继续朗读。
    ///
    /// **这是 D-93 遗留缺陷的修复**：此前 `speakCurrentSegment` 在排入 utterance 后
    /// 立即 `segmentIndex += 1`，导致一次调用把全部段排入队列，
    /// `currentCharOffset` 推进与实际朗读脱节。现在由系统回调驱动推进。
    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                             didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.advanceAfterSegmentFinished()
        }
    }

    /// 系统取消朗读（如被其他音频打断）→ 回到 idle。
    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                             didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            // 取消后不再继续，交由调用方决定是否恢复（避免死循环）
            self.segmentIndex = 0
            self.segments = []
            self.state = .idle
        }
    }
}
#endif

extension TTSEngine {
    /// 段读完推进（`didFinish` 调用）。
    @MainActor
    func advanceAfterSegmentFinished() {
        guard state == .speaking || state == .paused else { return }
        segmentIndex += 1
        if segmentIndex < segments.count {
            speakCurrentSegment()
        } else {
            // 全章读完
            let finished = onFinishedChapter
            stop()
            finished?()
        }
    }
}
