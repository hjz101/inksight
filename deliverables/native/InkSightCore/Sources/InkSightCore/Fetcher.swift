import Foundation

// MARK: - Fetcher（唯一出网门面，总册第 6 章「三个门面」之一）

/// 出网门面：**所有网络请求必须经 `Fetcher`**。
///
/// 目的：把「未成年人模式下整体断网」从一条条款变成**一个可 grep 的调用点清单**。
/// 全部网络访问都从 `Fetcher.fetch` 过；绕过门面直接用 `URLSession` 即违规
/// （单测以「源码扫描：业务层无 URLSession」兜底）。
///
/// 设计（保持 InkSightCore 零依赖）：
/// - **访问策略抽象**：门面不依赖 App 层的 `AgeGateState`，而是接受一个 `AccessPolicy`。
///   由 App 层把年龄态映射成策略（`.minorConfirmed` → `.denyAll`），
///   门面只负责"策略不允许就拒绝"——状态语义留在 App 层，门面保持纯逻辑。
/// - **NFR-04 纪律内置**：并发 ≤ `min(6, 源数)`、单源超时 8s、
///   `scenePhase != .active` 立即取消、BGTaskScheduler 不注册抓取。
public enum Fetcher {

    /// 出网访问策略（由 App 层按年龄态注入）。
    public enum AccessPolicy: Sendable, Equatable {
        /// 允许出网（按并发/超时纪律）。
        case allow
        /// 整体断网（未成年人模式 `denyAll`）——任何请求直接拒绝，不发起网络。
        case denyAll
    }

    /// 请求配置（NFR-04 并发与超时纪律的代码镜像）。
    public struct RequestConfig: Sendable {
        /// 单源超时（秒）。NFR-04：8s。
        public let timeoutSeconds: TimeInterval
        /// 最大并发源数。NFR-04：`min(6, 启用源数)`——门面按上限截断。
        public let maxConcurrentSources: Int

        public static let nfr04 = RequestConfig(timeoutSeconds: 8, maxConcurrentSources: 6)

        public init(timeoutSeconds: TimeInterval, maxConcurrentSources: Int) {
            self.timeoutSeconds = timeoutSeconds
            self.maxConcurrentSources = max(1, maxConcurrentSources)
        }
    }

    /// 出网结果。
    public enum FetchResult: Sendable {
        case success(Data)
        case failure(FetchError)
    }

    /// 出网错误。
    public enum FetchError: Error, Sendable, Equatable {
        /// 策略拒绝（未成年人模式 `denyAll`）——请求未发起。
        case deniedByPolicy
        /// 超时（NFR-04：单源 8s）。
        case timeout
        /// 传输失败（网络不可达、DNS、连接重置等）。
        case transport
        /// 非 2xx。
        case badStatus(Int)
    }

    // MARK: - 全局策略（App 层在启动/年龄态变化时设置）

    /// 当前全局访问策略。**默认 `.allow`**；App 层在 `AgeGateState` 变化时
    /// 把 `.minorConfirmed` 映射为 `.denyAll` 并写入。
    public nonisolated(unsafe) static var currentPolicy: AccessPolicy = .allow

    /// 当前全局请求配置（NFR-04）。
    public nonisolated(unsafe) static var currentConfig: RequestConfig = .nfr04

    // MARK: - 唯一出网入口

    /// **唯一出网入口**：发起一次 HTTP GET。
    ///
    /// - 策略 `.denyAll` → 直接 `.failure(.deniedByPolicy)`，不发起任何网络。
    /// - 超时按 `currentConfig.timeoutSeconds`（NFR-04：8s）。
    /// - 调用方必须持有返回的 `Task` 并在 `scenePhase != .active` 时取消
    ///   （NFR-04：`cancelAllTasks()`；门面不替调用方管理生命周期，但提供可取消句柄）。
    public static func fetch(_ url: URL,
                             timeout: TimeInterval? = nil) async -> FetchResult {
        guard currentPolicy == .allow else {
            return .failure(.deniedByPolicy)
        }
        let config = timeout.map {
            RequestConfig(timeoutSeconds: $0, maxConcurrentSources: currentConfig.maxConcurrentSources)
        } ?? currentConfig

        let request = URLRequest(url: url,
                                 timeoutInterval: config.timeoutSeconds)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return .failure(.badStatus(http.statusCode))
            }
            return .success(data)
        } catch let error as URLError where error.code == .timedOut {
            return .failure(.timeout)
        } catch {
            return .failure(.transport)
        }
    }

    /// 并发纪律的辅助判据（NFR-04：`min(6, 启用源数)`）——供调用方决定并发规模。
    public static func maxConcurrent(for enabledSources: Int) -> Int {
        min(currentConfig.maxConcurrentSources, max(0, enabledSources))
    }
}
