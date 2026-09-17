// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HarnessKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "HarnessCore", targets: ["HarnessCore"]),
        .library(name: "ClaudeHarness", targets: ["ClaudeHarness"]),
        .executable(name: "harness-probe", targets: ["harness-probe"]),
    ],
    targets: [
        .target(name: "HarnessCore"),
        .testTarget(name: "HarnessCoreTests", dependencies: ["HarnessCore"]),
        .target(name: "ClaudeHarness", dependencies: ["HarnessCore"]),
        .testTarget(
            name: "ClaudeHarnessTests",
            dependencies: ["ClaudeHarness", "HarnessCore"],
            // Fixtures gravados pelo harness-probe (Task 4): transcritos reais
            // de sessões do `claude`, consumidos pelo próximo plano (protocolo
            // de controle e mapper de eventos). SwiftPM não os inclui como
            // fonte automaticamente — precisam ser declarados como recurso.
            resources: [.copy("Fixtures")]
        ),
        .executableTarget(name: "harness-probe", dependencies: ["ClaudeHarness"]),
    ]
)
