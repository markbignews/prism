// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PrismCLI",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "prism", targets: ["PrismCLI"]),
    ],
    targets: [
        .executableTarget(
            name: "PrismCLI",
            path: "Sources",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"]),
            ]
        ),
    ]
)
