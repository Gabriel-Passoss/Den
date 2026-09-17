// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HarnessKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "HarnessCore", targets: ["HarnessCore"]),
        .library(name: "ClaudeHarness", targets: ["ClaudeHarness"]),
    ],
    targets: [
        .target(name: "HarnessCore"),
        .testTarget(name: "HarnessCoreTests", dependencies: ["HarnessCore"]),
        .target(name: "ClaudeHarness", dependencies: ["HarnessCore"]),
        .testTarget(name: "ClaudeHarnessTests", dependencies: ["ClaudeHarness", "HarnessCore"]),
    ]
)
