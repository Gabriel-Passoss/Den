// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HarnessKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "HarnessCore", targets: ["HarnessCore"]),
        .library(name: "ClaudeHarness", targets: ["ClaudeHarness"]),
        .library(name: "OpenCodeHarness", targets: ["OpenCodeHarness"]),
        .library(name: "DenStore", targets: ["DenStore"]),
        .library(name: "DenMemory", targets: ["DenMemory"]),
        .executable(name: "harness-probe", targets: ["harness-probe"]),
    ],
    targets: [
        .target(name: "HarnessCore"),
        .target(name: "HarnessTestSupport"),
        .testTarget(
            name: "HarnessCoreTests",
            dependencies: ["HarnessCore", "HarnessTestSupport", "DenStore"]
        ),
        .target(name: "ClaudeHarness", dependencies: ["HarnessCore"]),
        .testTarget(
            name: "ClaudeHarnessTests",
            dependencies: ["ClaudeHarness", "HarnessCore", "HarnessTestSupport", "DenStore"],

            resources: [.copy("Fixtures")]
        ),

        .target(name: "OpenCodeHarness", dependencies: ["HarnessCore"]),
        .testTarget(
            name: "OpenCodeHarnessTests",
            dependencies: ["OpenCodeHarness", "HarnessCore", "HarnessTestSupport"],

            resources: [.copy("Fixtures")]
        ),

        .target(name: "SQLiteKit"),
        .testTarget(name: "SQLiteKitTests", dependencies: ["SQLiteKit"]),

        .target(name: "DenStore", dependencies: ["HarnessCore", "SQLiteKit"]),
        .testTarget(name: "DenStoreTests", dependencies: ["DenStore", "HarnessCore", "SQLiteKit"]),

        .target(name: "DenMemory", dependencies: ["HarnessCore"]),
        .testTarget(name: "DenMemoryTests", dependencies: ["DenMemory", "HarnessCore"]),

        .target(name: "HarnessProbeArguments"),
        .testTarget(name: "HarnessProbeArgumentsTests", dependencies: ["HarnessProbeArguments"]),

        .executableTarget(
            name: "harness-probe",
            dependencies: ["ClaudeHarness", "HarnessCore", "HarnessProbeArguments"]
        ),
    ]
)
