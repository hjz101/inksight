import SwiftUI
import InkSightAppKit
import InkSightCore

/// 后台重排状态模型（开发包 #8）：承载调度器 ＋ 主线程状态呈现。
///
/// 分工：**调度在后台线程**（`RepaginationScheduler`——可取消、1 章/次、正文按需取），
/// **状态在主线程呈现**（本模型）。二者用轮询解耦，避免后台回调把 UI 状态跨 actor 边界搬运。
///
/// 线程约定：本类为 `@unchecked Sendable`（可安全跨线程传递引用），
/// 但**所有 `@Published` 的写入都发生在主线程**（`start`／`cancel` 由 UI 调用，
/// 轮询 `Task` 显式标注 `@MainActor`）。
final class RepaginationStatusModel: ObservableObject, @unchecked Sendable {

    /// 后台调度器（可取消；1 章/次；正文按需取）。
    let scheduler = RepaginationScheduler()

    /// 状态文案（用户可读）：进行中／已完成／已取消／诚实空态。
    @Published var statusText: String = ""

    /// 已处理章数。
    @Published var processedCount: Int = 0

    /// 本次调度总章数。
    @Published var totalCount: Int = 0

    private var pollTask: Task<Void, Never>?

    /// 启动后台重排（入队 ＋ 调度）。
    ///
    /// - Parameter chapters: 待重排章；**只提供取正文的闭包**（正文不在入队时物化，NFR-09 ②）。
    func start(chapters: [(id: Int, textProvider: () -> String?)],
               typography: ReaderTypography,
               containerSize: CGSize,
               screenScale: Double) {
        pollTask?.cancel()
        let total = scheduler.start(chapters: chapters,
                                    typography: typography,
                                    containerSize: containerSize,
                                    screenScale: screenScale)
        totalCount = total
        processedCount = 0
        statusText = "后台重排中：0/\(total) 章"
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self else { return }
                let done = self.scheduler.processedChapterCount
                let totalNow = self.scheduler.totalChapterCount
                self.processedCount = done
                self.totalCount = totalNow
                switch self.scheduler.state {
                case .running:
                    self.statusText = "后台重排中：\(done)/\(totalNow) 章"
                case .completed:
                    self.statusText = "后台重排完成：\(done)/\(totalNow) 章"
                    return
                case .cancelled:
                    self.statusText = "后台重排已取消：\(done)/\(totalNow) 章"
                    return
                case .idle:
                    self.statusText = ""
                    return
                }
            }
        }
    }

    /// 取消后台重排（立即停止处理下一章；已在处理的那一章跑完即止）。
    func cancel() {
        scheduler.cancel()
        pollTask?.cancel()
        pollTask = nil
        statusText = "后台重排已取消：\(processedCount)/\(totalCount) 章"
    }
}
