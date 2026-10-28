import XCTest
@testable import InkSightCore

/// 落盘单门 CI 门禁（总册第 6 章「三个门面」之二，架构勘误 E-04）。
final class PersistTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inksight-persist-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    /// 门面能原子写入并自动建目录（含多级不存在的目录）。
    func testWriteCreatesDirectoryAndPersistsData() throws {
        let nested = tempDir.appendingPathComponent("a/b/c/file.json")
        let payload = Data("{\"k\":1}".utf8)
        let result = Persist.write(payload, to: nested, payload: .readingProgress,
                                   excludedFromBackup: false)
        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(try Data(contentsOf: nested), payload, "写入内容必须可原样读回")
    }

    /// 每次写入都是原子替换：先写 A 再写 B，读回必须是 B（不是 A、不是空）。
    func testWriteIsAtomicReplace() throws {
        let file = tempDir.appendingPathComponent("x.json")
        XCTAssertNoThrow(try Persist.write(Data("A".utf8), to: file,
                                           payload: .notes, excludedFromBackup: false).get())
        XCTAssertNoThrow(try Persist.write(Data("B".utf8), to: file,
                                           payload: .notes, excludedFromBackup: false).get())
        XCTAssertEqual(try Data(contentsOf: file), Data("B".utf8))
    }

    /// **类型层禁令**：`Payload` 不得提供任何"正文"类 case。
    ///
    /// E-04 原文：「第三方正文」这个类型在产品层不允许存在——不是禁用，是类型里没有。
    /// 本测试用源码反射式断言：枚举 case 名里不得出现正文/内容语义。
    func testPayloadTypeHasNoBodyContentCase() {
        // Payload 不是 CaseIterable（含关联值枚举无关联值的才有 allCases），
        // 故改用「源码扫描 Persist.swift 的 case 声明」验证。
        let source = try? String(contentsOf: persistSourceURL(), encoding: .utf8)
        let src = source ?? ""
        XCTAssertFalse(src.isEmpty, "必须能读到 Persist.swift 源码")
        for forbidden in ["case thirdPartyContent", "case bodyText", "case chapterBody",
                          "case contentBody", "case novelText"] {
            XCTAssertFalse(src.contains(forbidden),
                           "Payload 不得提供正文类 case（E-04）：\(forbidden)")
        }
        // 正向：必须存在这 6 个合法类型
        for required in ["case userFile", "case readingProgress", "case notes",
                         "case typographyPreference", "case motionPreference",
                         "case structuralMetadata"] {
            XCTAssertTrue(src.contains(required), "Payload 必须提供：\(required)")
        }
    }

    /// **CI 门禁：业务层不得裸写盘**。
    ///
    /// E-04：绕过 `Persist` 直写 `FileManager` 即违规。扫描 InkSightApp 的全部源文件，
    /// 除 `Persist` 门面自身外，不得出现裸 `.write(to:` / `createDirectory` / `setResourceValues`。
    func testBusinessLayerHasNoBareDiskWrites() throws {
        let sourcesRoot = try appSourcesRoot()
        var violations: [String] = []
        let fm = FileManager.default
        guard let en = fm.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil) else {
            return XCTFail("无法枚举源码目录：\(sourcesRoot.path)")
        }
        for case let url as URL in en where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            // 去掉注释行，避免注释里提到这些 API 造成误报
            let codeLines = text.split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
                .filter { line in
                    let t = line.trimmingCharacters(in: .whitespaces)
                    return !t.hasPrefix("//") && !t.hasPrefix("///") && !t.hasPrefix("*")
                }
            let code = codeLines.joined(separator: "\n")
            if code.contains(".write(to:") { violations.append("\(url.lastPathComponent): .write(to:") }
            if code.contains("createDirectory(at:") { violations.append("\(url.lastPathComponent): createDirectory") }
            if code.contains("setResourceValues(") { violations.append("\(url.lastPathComponent): setResourceValues") }
        }
        XCTAssertTrue(violations.isEmpty,
                      "写盘必须经 Persist 门面（E-04），发现裸写盘：\n" + violations.joined(separator: "\n"))
    }

    // MARK: - 路径辅助

    private func persistSourceURL() -> URL {
        // #filePath = .../InkSightCore/Tests/InkSightCoreTests/PersistTests.swift
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // InkSightCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // InkSightCore（包根）
            .appendingPathComponent("Sources/InkSightCore/Persist.swift")
    }

    private func appSourcesRoot() throws -> URL {
        // ../InkSightApp/Sources（与 InkSightCore 同级包）
        let coreRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // InkSightCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // InkSightCore（包根）
            .deletingLastPathComponent()   // native
        let appSources = coreRoot
            .appendingPathComponent("InkSightApp/Sources")
        guard FileManager.default.fileExists(atPath: appSources.path) else {
            throw NSError(domain: "PersistTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "找不到 \(appSources.path)"])
        }
        return appSources
    }
}
