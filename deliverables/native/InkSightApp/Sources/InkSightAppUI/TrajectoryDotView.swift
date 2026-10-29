import SwiftUI
import InkSightAppKit

// MARK: - ReadingTrajectoryDot（FR-023 阅读轨迹切换点）

/// 阅读轨迹上的**文件切换点**（FR-023）。
///
/// **规格（PRD 原文，逐条都是"克制"要求）**：
/// - **6pt 中性圆点**，颜色 `--ink-text-3`（三级文字色）；
/// - **不用红/强调色、无脉冲、无角标**；
/// - **间距 <12pt 合并**为一个点 ＋「+N」；
/// - 点击**只出中性说明**「此处切换过文件」；
/// - **不显示版本优劣、不做文件名对比、不给"找更好的"引导**。
///
/// **为什么这么克制**：PRD 写明「标红是自曝（截图即缺陷证据），并把用户往
/// 『找更好的源』上推」——这个点是**中性事实记录**，不是质量评价。
public struct TrajectoryDot: Identifiable, Equatable, Sendable {
    /// 在轨迹轴上的位置（0…1）。
    public let position: Double
    /// 该位置合并了多少次切换（≥1）。
    public let count: Int
    public var id: String { "\(position)-\(count)" }

    public init(position: Double, count: Int = 1) {
        self.position = position
        self.count = max(1, count)
    }
}

/// 轨迹点视图（单个点）。
public struct TrajectoryDotView: View {
    public let dot: TrajectoryDot
    /// 是否展开显示说明。
    public let isExpanded: Bool

    /// 点直径（PRD：**6pt**）。
    public nonisolated static let diameter: CGFloat = 6
    /// 合并阈值（PRD：间距 **<12pt** 合并）。
    public nonisolated static let mergeThreshold: CGFloat = 12

    public init(dot: TrajectoryDot, isExpanded: Bool = false) {
        self.dot = dot
        self.isExpanded = isExpanded
    }

    public var body: some View {
        VStack(spacing: 4) {
            if isExpanded {
                // **中性说明**：只说事实，不评价、不引导
                Text("此处切换过文件")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 4))
            }
            HStack(spacing: 2) {
                Circle()
                    // 三级文字色（--ink-text-3 语义）；**不用强调色/红**
                    .fill(Color.secondary.opacity(0.55))
                    .frame(width: Self.diameter, height: Self.diameter)
                if dot.count > 1 {
                    // 合并计数：+N（**无角标样式、无红点**，只是文字）
                    Text("+\(dot.count - 1)")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dot.count > 1
                            ? "此处切换过文件 \(dot.count) 次"
                            : "此处切换过文件")
    }
}

// MARK: - 合并算法

public enum TrajectoryMerge {

    /// 把原始切换位置按**间距 <12pt** 合并成点。
    ///
    /// - Parameters:
    ///   - positions: 切换点在轨迹轴上的像素位置（已按轴长换算）。
    ///   - threshold: 合并阈值（PRD：12pt）。
    /// - Returns: 合并后的点（位置取组内均值，count 为组内数量）。
    public static func merge(_ positions: [CGFloat],
                             threshold: CGFloat = TrajectoryDotView.mergeThreshold) -> [TrajectoryDot] {
        guard !positions.isEmpty else { return [] }
        let sorted = positions.sorted()
        var groups: [[CGFloat]] = [[sorted[0]]]
        for p in sorted.dropFirst() {
            if let last = groups[groups.count - 1].last, p - last < threshold {
                groups[groups.count - 1].append(p)
            } else {
                groups.append([p])
            }
        }
        return groups.compactMap { group in
            guard !group.isEmpty else { return nil }
            let mean = group.reduce(0, +) / CGFloat(group.count)
            return TrajectoryDot(position: Double(mean), count: group.count)
        }
    }
}
