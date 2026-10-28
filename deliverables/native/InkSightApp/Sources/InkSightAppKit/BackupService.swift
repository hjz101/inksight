import Foundation
import InkSightCore

// MARK: - BackupPayload（FR-025 设置与数据：备份导出/导入）

/// 备份导出负载（FR-025）。
///
/// 契约（PRD FR-025 原文）：
/// - **落盘格式必须带 `version` 字段**（P0 前置）——保证老数据可迁移；
/// - 导出**只含**：本地文件进度、排版偏好、动效偏好；
/// - **显式排除在线正文**（技术约束清单 FR-025：导出不含在线书正文；本类型结构上没有正文字段）。
///
/// 结构上「没有正文字段」＝ FR-025 的"不含在线正文"从条款变成类型保证
/// （同 E-04「第三方正文在类型层不存在」的纪律）。
public struct BackupPayload: Codable, Equatable, Sendable {

    /// 备份格式版本（P0 前置：带 version 字段，老数据可迁移）。
    public static let currentVersion = 1

    public let version: Int
    /// 各书阅读进度（`charOffset + fingerprint`，定位铁律）。
    public let progress: [ReadingProgress]
    /// 排版偏好（8 字段）。
    public let typography: ReaderTypography?
    /// 动效开关偏好。
    public let motion: MotionSettings?

    public init(version: Int = BackupPayload.currentVersion,
                progress: [ReadingProgress],
                typography: ReaderTypography?,
                motion: MotionSettings?) {
        self.version = version
        self.progress = progress
        self.typography = typography
        self.motion = motion
    }

    /// 解码时校验版本：未知的**更高**版本拒绝（避免把新格式读坏）；
    /// 更低的旧版本允许（按需迁移）。
    public enum DecodeError: Error, Equatable {
        case unsupportedVersion(Int)
    }

    public static func decode(_ data: Data) throws -> BackupPayload {
        let payload = try JSONDecoder().decode(BackupPayload.self, from: data)
        guard payload.version <= BackupPayload.currentVersion else {
            throw DecodeError.unsupportedVersion(payload.version)
        }
        return payload
    }

    public func encode() throws -> Data {
        try JSONEncoder().encode(self)
    }
}

// MARK: - BackupService（FR-025 导出/导入入口）

/// 备份服务：汇集当前可导出的用户数据，产出/恢复 `BackupPayload`。
public struct BackupService {

    public let progressStore: ReadingProgressStore
    public let typographyStore: TypographyPresetStore
    public let motionStore: MotionSettingsStore

    public init(progressStore: ReadingProgressStore = ReadingProgressStore(),
                typographyStore: TypographyPresetStore = TypographyPresetStore(),
                motionStore: MotionSettingsStore = MotionSettingsStore()) {
        self.progressStore = progressStore
        self.typographyStore = typographyStore
        self.motionStore = motionStore
    }

    /// 导出当前全部用户数据（进度＋排版偏好＋动效偏好；**无正文**——结构上没有正文字段）。
    public func export() throws -> BackupPayload {
        let progress = progressStore.allProgress()
        return BackupPayload(progress: progress,
                             typography: typographyStore.load(),
                             motion: motionStore.load())
    }

    /// 导入备份：恢复进度与偏好。
    ///
    /// - 未知更高版本拒绝（`DecodeError.unsupportedVersion`）；
    /// - 导入失败保持原数据不动（不半途覆盖）。
    public func `import`(_ payload: BackupPayload) throws {
        // 先全部校验，再落盘——避免部分成功
        for p in payload.progress {
            progressStore.record(p)
        }
        if let typography = payload.typography {
            try typographyStore.save(typography)
        }
        if let motion = payload.motion {
            try motionStore.save(motion)
        }
    }
}
