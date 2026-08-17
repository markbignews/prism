// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Prism",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Prism", targets: ["Prism"]),
    ],
    targets: [
        .executableTarget(
            name: "Prism",
            path: "Sources/Prism",
            linkerSettings: [
                // 打包要求：最低 macOS 15、最高 27（以 27 SDK 链接）。
                // 显式写 -platform_version，确保 LC_BUILD_VERSION 记录
                // sdk=27.0 —— 否则系统会把应用当旧 SDK 应用，macOS 26+
                // 不会启用 Liquid Glass 窗口效果。
                .unsafeFlags([
                    "-Xlinker", "-platform_version",
                    "-Xlinker", "macos",
                    "-Xlinker", "15.0",
                    "-Xlinker", "27.0",
                ])
            ]
        ),
    ]
)
