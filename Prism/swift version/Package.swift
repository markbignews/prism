// swift-tools-version: 6.0

import PackageDescription
import Foundation

// SwiftPM's Swift Build engine can otherwise record sdk=15.0 (the deployment
// target) in LC_BUILD_VERSION. Use the selected SDK's real version; never claim
// to have linked against a hard-coded future SDK.
let sdkQuery = Process()
let sdkOutput = Pipe()
sdkQuery.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
sdkQuery.arguments = ["--no-cache", "--sdk", "macosx", "--show-sdk-version"]
sdkQuery.standardOutput = sdkOutput
try sdkQuery.run()
let sdkVersion = String(decoding: sdkOutput.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    .trimmingCharacters(in: .whitespacesAndNewlines)
sdkQuery.waitUntilExit()
guard sdkQuery.terminationStatus == 0,
      sdkVersion.range(of: #"^\d+\.\d+(\.\d+)?$"#, options: .regularExpression) != nil else {
    fatalError("Cannot determine the selected macOS SDK. Check xcode-select and xcrun.")
}

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
            path: "Sources/Prism",
            linkerSettings: [.unsafeFlags([
                "-Xlinker", "-platform_version", "-Xlinker", "macos",
                "-Xlinker", "15.0", "-Xlinker", sdkVersion
            ])]
        ),
        .testTarget(name: "PrismTests", dependencies: ["Prism"]),
    ]
)
