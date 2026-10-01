import Foundation
import HarnessCore

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

    public func quickPromptArguments(for instruction: String) -> [String]? {
        ["-p", instruction, "--model", "haiku",
         "--safe-mode", "--tools", "", "--no-session-persistence"]
    }

    public func makeSession(installation: HarnessInstallation,
                            workingDirectory: URL,
                            settings: [String: String]) -> any HarnessSession {
        ClaudeSession(installation: installation,
                      workingDirectory: workingDirectory,
                      settings: settings)
    }
}
