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
            path: "Sources/Prism"
        ),
    ]
)
