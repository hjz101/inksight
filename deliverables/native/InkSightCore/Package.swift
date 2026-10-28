// swift-tools-version:6.2
// InkSightCore · 墨见 InkSight 排版引擎核心（开发包 #1，依 D-53）
// 对齐：技术约束清单 v1.1（FR-031 / NFR-01 / 02 / 03 / 08）、架构冻结版 v2.6 勘误 E-01～E-04
import PackageDescription

let package = Package(
    name: "InkSightCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        // 供 InkSightApp 跨包引用（D-53 开发包 #2）；仅产品化声明，不触碰任何类型与测试（契约冻结不动）
        .library(name: "InkSightCore", targets: ["InkSightCore"]),
    ],
    targets: [
        .target(name: "InkSightCore", path: "Sources/InkSightCore"),
        .testTarget(name: "InkSightCoreTests", dependencies: ["InkSightCore"], path: "Tests/InkSightCoreTests"),
    ],
    swiftLanguageModes: [.v5]
)
