import Foundation
import HarnessCore

public enum ClaudeKnobs {
    public static let model = "model"
    public static let effort = "effort"
    public static let mode = "mode"

    static let modelOptions: [HarnessKnob.Option] = [
        .init(value: "fable", label: "Fable"),
        .init(value: "opus", label: "Opus"),
        .init(value: "sonnet", label: "Sonnet"),
        .init(value: "haiku", label: "Haiku"),
    ]

    static let effortOptions: [HarnessKnob.Option] = [
        .init(value: "low", label: "Baixo"),
        .init(value: "medium", label: "Médio"),
        .init(value: "high", label: "Alto"),
        .init(value: "xhigh", label: "Muito alto"),
        .init(value: "max", label: "Máximo"),
    ]

    static let modeOptions: [HarnessKnob.Option] = [
        .init(value: PermissionMode.manual.rawValue, label: "Manual"),
        .init(value: PermissionMode.acceptEdits.rawValue, label: "Aceitar edições"),
        .init(value: PermissionMode.auto.rawValue, label: "Automático"),
        .init(value: PermissionMode.plan.rawValue, label: "Plano"),
        .init(value: PermissionMode.dontAsk.rawValue, label: "Não perguntar"),
        .init(value: PermissionMode.bypassPermissions.rawValue, label: "Sem permissões"),
    ]

    public static func all(
        settings: [String: String],
        detected: (effort: EffortLevel?, mode: PermissionMode?) = (nil, nil)
    ) -> [HarnessKnob] {
        [
            HarnessKnob(id: model, category: .model, name: "Modelo",
                        currentValue: settings[model], options: modelOptions),
            HarnessKnob(id: effort, category: .effort, name: "Esforço",
                        currentValue: settings[effort] ?? detected.effort?.rawValue,
                        options: effortOptions),
            HarnessKnob(id: mode, category: .mode, name: "Permissão",
                        currentValue: settings[mode] ?? detected.mode?.rawValue,
                        options: modeOptions),
        ]
    }
}

public struct ClaudeCodeHarness: Harness {
    public init() {}

    public var id: HarnessID { .claudeCode }
    public var displayName: String { "Claude Code" }

    public func discover() async throws -> HarnessInstallation {
        try await ClaudeDiscovery().discover()
    }

    public func capabilities(for installation: HarnessInstallation) -> HarnessCapabilities {
        ClaudeLaunch.capabilities(for: installation)
    }

    public func knobs(for installation: HarnessInstallation,
                      workingDirectory: URL) -> [HarnessKnob] {
        ClaudeKnobs.all(settings: [:], detected: (
            effort: ClaudeSettings.effortLevel(forWorkingDirectory: workingDirectory),
            mode: ClaudeSettings.permissionMode(forWorkingDirectory: workingDirectory)
        ))
    }

    public func titleArguments(for instruction: String) -> [String]? {
        ["-p", instruction, "--model", "haiku"]
    }

    public func makeSession(installation: HarnessInstallation,
                            workingDirectory: URL,
                            settings: [String: String]) -> any HarnessSession {
        ClaudeSession(installation: installation,
                      workingDirectory: workingDirectory,
                      settings: settings)
    }
}
