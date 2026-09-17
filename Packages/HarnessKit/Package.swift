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
        .target(name: "HarnessTestSupport"),
        .testTarget(
            name: "HarnessCoreTests",
            dependencies: ["HarnessCore", "HarnessTestSupport"]
        ),
        .target(name: "ClaudeHarness", dependencies: ["HarnessCore"]),
        .testTarget(
            name: "ClaudeHarnessTests",
            dependencies: ["ClaudeHarness", "HarnessCore", "HarnessTestSupport"],
            // Fixtures gravados pelo harness-probe (Task 4): transcritos reais
            // de sessões do `claude`, consumidos pelo próximo plano (protocolo
            // de controle e mapper de eventos). SwiftPM não os inclui como
            // fonte automaticamente — precisam ser declarados como recurso.
            resources: [.copy("Fixtures")]
        ),
        // Lógica de parsing de `harness-probe record`, isolada de main.swift
        // porque um alvo executável com um arquivo `main.swift` (código de
        // topo) não pode ser importado por um alvo de teste. A ambiguidade
        // que causou dois lançamentos reais não intencionais do `claude`
        // vivia exatamente nessa lógica — precisa ser testável.
        .target(name: "HarnessProbeArguments"),
        .testTarget(name: "HarnessProbeArgumentsTests", dependencies: ["HarnessProbeArguments"]),
        // `HarnessCore` é explícito, e não herdado pelo fechamento transitivo
        // do SwiftPM: o alvo faz `import HarnessCore` direto, e um manifesto
        // que não diz isso mente sobre o que o alvo usa — no dia em que
        // `ClaudeHarness` deixar de arrastá-lo junto, o probe quebra por uma
        // razão que não está escrita em lugar nenhum.
        .executableTarget(
            name: "harness-probe",
            dependencies: ["ClaudeHarness", "HarnessCore", "HarnessProbeArguments"]
        ),
    ]
)
