// swift-tools-version:6.2
// InkSightApp · 墨见 InkSight iOS App 骨架（开发包 #2，依 D-53）
// 依赖已冻结的 InkSightCore（契约不改——本文件仅为其补 products 声明以供跨包引用，见回报说明）
import PackageDescription

let package = Package(
    name: "InkSightApp",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "InkSightAppKit", targets: ["InkSightAppKit"]),
        .library(name: "InkSightAppUI", targets: ["InkSightAppUI"]),
    ],
    dependencies: [
        .package(path: "../InkSightCore")
    ],
    targets: [
        // 纯逻辑层（无 SwiftUI 依赖）：MotionRegistry / AgeGate 矩阵 / GlassSpec / 数据层（ReadingProgressStore / BookShelfStore / SQLiteCache）。
        // 系统 sqlite3 通过平台 SQLite3 模块 + linkerSettings -lsqlite3 链接（开发包 #3：不 vendored、不另起 systemLibrary 目标，
        // 因 Apple SDK 已提供 SQLite3 模块，跨 macOS swift build 与 iOS Simulator SDK build 均稳定）。
        // 依赖 InkSightCore：数据层复用 PageAnchor / ChapterAnchor / ChapterScanner（契约冻结不动）。
        .target(
            name: "InkSightAppKit",
            dependencies: [
                .product(name: "InkSightCore", package: "InkSightCore"),
            ],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        // SwiftUI 层（App 骨架 / GlassSurface / AgeGate 视图 / MotionCoordinator）
        .target(name: "InkSightAppUI", dependencies: ["InkSightAppKit", "InkSightCore"]),
        .executableTarget(name: "InkSightAppMain", dependencies: ["InkSightAppUI", "InkSightAppKit", "InkSightCore"], path: "Sources/InkSightAppMain"),
        .testTarget(name: "InkSightAppKitTests", dependencies: ["InkSightAppKit"]),
        .testTarget(name: "InkSightAppUITests", dependencies: ["InkSightAppUI", "InkSightAppKit"]),
    ]
)
