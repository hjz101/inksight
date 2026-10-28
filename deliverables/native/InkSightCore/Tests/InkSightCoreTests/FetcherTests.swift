import XCTest
@testable import InkSightCore

/// 出网门面测试（总册第 6 章「三个门面」之一）。
final class FetcherTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Fetcher.currentPolicy = .allow
        Fetcher.currentConfig = .nfr04
    }

    /// **未成年人模式 denyAll**：策略拒绝时请求直接失败、不发起网络。
    func testDenyAllRejectsWithoutNetwork() async {
        Fetcher.currentPolicy = .denyAll
        let result = await Fetcher.fetch(URL(string: "https://example.com/x")!)
        guard case .failure(let error) = result else {
            return XCTFail("denyAll 下请求必须被拒绝")
        }
        XCTAssertEqual(error, .deniedByPolicy)
    }

    /// 策略恢复 allow 后请求正常发起（不卡死在拒绝态）。
    func testAllowAfterDenyResumesNetwork() async {
        Fetcher.currentPolicy = .denyAll
        _ = await Fetcher.fetch(URL(string: "https://example.com/x")!)
        Fetcher.currentPolicy = .allow
        // 不真正出网（测试环境无网），只验证不再被策略拒绝：
        // 失败类型应是 transport/timeout 而非 deniedByPolicy。
        let result = await Fetcher.fetch(URL(string: "https://127.0.0.1:1/x")!, timeout: 1)
        guard case .failure(let error) = result else {
            return XCTFail("本地不可达应失败")
        }
        XCTAssertNotEqual(error, .deniedByPolicy,
                          "allow 策略下失败应是传输/超时，而不是策略拒绝")
    }

    /// **NFR-04 并发纪律**：`min(6, 启用源数)`。
    func testMaxConcurrentFollowsNFR04() {
        XCTAssertEqual(Fetcher.maxConcurrent(for: 10), 6, "启用 10 源 → 上限 6")
        XCTAssertEqual(Fetcher.maxConcurrent(for: 3), 3, "启用 3 源 → 3")
        XCTAssertEqual(Fetcher.maxConcurrent(for: 0), 0, "启用 0 源 → 0")
    }

    /// NFR-04 默认配置：单源超时 8s。
    func testDefaultConfigMatchesNFR04() {
        XCTAssertEqual(Fetcher.currentConfig.timeoutSeconds, 8, "NFR-04 单源超时 8s")
        XCTAssertEqual(Fetcher.currentConfig.maxConcurrentSources, 6)
    }

    /// **CI 门禁：业务层不得裸 URLSession**。
    ///
    /// 总册 Fetcher 门面：唯一出网入口。绕过门面直接用 `URLSession` 即违规。
    /// 扫描 InkSightApp/Sources（去注释后），除 Fetcher.swift 自身外不得出现 URLSession。
    func testBusinessLayerHasNoBareURLSession() throws {
        let appSources = try appSourcesRoot()
        var violations: [String] = []
        let fm = FileManager.default
        guard let en = fm.enumerator(at: appSources, includingPropertiesForKeys: nil) else {
            return XCTFail("无法枚举：\(appSources.path)")
        }
        for case let url as URL in en where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let codeLines = text.split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
                .filter { line in
                    let t = line.trimmingCharacters(in: .whitespaces)
                    return !t.hasPrefix("//") && !t.hasPrefix("///") && !t.hasPrefix("*")
                }
            let code = codeLines.joined(separator: "\n")
            if code.contains("URLSession") {
                violations.append("\(url.lastPathComponent): URLSession")
            }
        }
        XCTAssertTrue(violations.isEmpty,
                      "出网必须经 Fetcher 门面，发现裸 URLSession：\n" + violations.joined(separator: "\n"))
    }

    // MARK: - 路径辅助

    private func appSourcesRoot() throws -> URL {
        // #filePath = .../InkSightCore/Tests/InkSightCoreTests/FetcherTests.swift
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // InkSightCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // InkSightCore
            .deletingLastPathComponent()   // native
            .appendingPathComponent("InkSightApp/Sources")
    }
}
