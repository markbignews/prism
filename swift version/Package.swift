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
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
        .executableTarget(
            name: "Prism",
            dependencies: ["CSQLite"],
            path: "Sources/Prism"
        ),
        .testTarget(name: "PrismTests", dependencies: ["Prism"]),
    ]
)
