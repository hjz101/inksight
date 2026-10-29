import Foundation
import InkSightCore

// MARK: - TrajectoryLog（FR-023 阅读轨迹的切换点记录）

/// 阅读轨迹**切换点日志**（FR-023）。
///
/// 只记录**事实**：某本书在阅读进度比例 x 处发生过文件切换。
/// **不记录任何评价信息**——PRD 明确「不显示版本优劣、不做文件名对比、
/// 不给『找更好的』引导」。所以本类型**刻意不存 bookID/文件名/版本标签**，
/// 只存「位置比例 + 次数」：既满足需求，又在结构上杜绝了将来被拿去比较的可能。
public struct TrajectoryLog {

    /// 一次切换事件（只含位置比例，无身份信息）。
    public struct SwitchPoint: Codable, Equatable, Sendable {
        /// 全书进度比例（0…1）——切换发生时的阅读位置。
        public let progressRatio: Double
        public let timestamp: Date

        public init(progressRatio: Double, timestamp: Date = Date()) {
            self.progressRatio = min(max(progressRatio, 0), 1)
            self.timestamp = timestamp
        }
    }

    /// 保存的切换点（按 progressRatio 排序）。
    public private(set) var points: [SwitchPoint] = []
    private let fileURL: URL?

    public static let defaultDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("com.inksight/trajectory", isDirectory: true)
    }()

    public static let defaultFileName = "Trajectory.json"

    public init(fileURL: URL? = TrajectoryLog.defaultDirectory
        .appendingPathComponent(TrajectoryLog.defaultFileName)) {
        self.fileURL = fileURL
        if let fileURL { try? load(from: fileURL) }
    }

    /// 记录一次切换（传进度比例）。
    ///
    /// - Parameter progressRatio: 全书进度 0…1（由调用方按 charOffset/总长算）。
    public mutating func recordSwitch(at progressRatio: Double) throws {
        let point = SwitchPoint(progressRatio: progressRatio)
        points.append(point)
        points.sort { $0.progressRatio < $1.progressRatio }
        if let fileURL { try persist(to: fileURL) }
    }

    /// 全部切换点。
    public var allPoints: [SwitchPoint] { points }

    /// 清空（用户主动清除轨迹）。
    public mutating func clear() throws {
        points.removeAll()
        if let fileURL { try persist(to: fileURL) }
    }

    // MARK: - 持久化

    private func persist(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(points)
        // 轨迹是用户行为记录（属用户数据）→ 可备份
        try Persist.write(data, to: url, payload: .notes, excludedFromBackup: false).get()
    }

    private mutating func load(from url: URL) throws {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([SwitchPoint].self, from: data) else { return }
        points = decoded.sorted { $0.progressRatio < $1.progressRatio }
    }
}

// MARK: - 与轨迹点视图的桥接

/// 把 `TrajectoryLog` 的切换点换算成可渲染的 `TrajectoryDot`（含 <12pt 合并）。
public enum TrajectoryRenderer {

    /// 把日志换成点（需要轨迹轴的像素长度来算间距）。
    ///
    /// - Parameters:
    ///   - log: 切换点日志。
    ///   - axisLength: 轨迹轴像素长度（用于把 0…1 比例换成像素位置）。
    /// - Returns: 合并后的点（间距 <12pt 的合并为一个，count 记录次数）。
    @MainActor
    public static func dots(from log: TrajectoryLog, axisLength: CGFloat) -> [TrajectoryDot] {
        let pixelPositions = log.allPoints.map { CGFloat($0.progressRatio) * axisLength }
        let merged = TrajectoryMerge.merge(pixelPositions)
        // 换算回 0…1 比例
        return merged.map {
            TrajectoryDot(position: Double($0.position / max(axisLength, 1)), count: $0.count)
        }
    }
}
