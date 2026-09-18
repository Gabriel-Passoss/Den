import Foundation
import HarnessCore

public enum SessionStart: Sendable, Equatable {

    case fresh(sessionID: UUID)

    case resume(harnessSessionID: UUID)

    case fork(from: UUID, newSessionID: UUID)
}

public enum EffortLevel: String, Sendable, Equatable, CaseIterable {
    case low, medium, high, xhigh, max
}

public enum ClaudeLaunch {
    public static func make(
        installation: HarnessInstallation,
        workingDirectory: URL,
        session: SessionStart,
        model: String? = nil,
        effort: EffortLevel? = nil,
        permissionMode: PermissionMode? = nil,
        additionalDirectories: [URL] = []
    ) -> ProcessTransport.Launch {
        var arguments = [
            "-p",
            "--output-format", "stream-json",
            "--input-format", "stream-json",
            "--include-partial-messages",
            "--verbose",

            "--permission-prompt-tool", "stdio",
        ]

        switch session {
        case .fresh(let sessionID):
            arguments += ["--session-id", sessionID.uuidString.lowercased()]
        case .resume(let harnessSessionID):

            arguments += ["--resume", harnessSessionID.uuidString.lowercased()]
        case .fork(let from, let newSessionID):
            arguments += [
                "--resume", from.uuidString.lowercased(),
                "--fork-session",
                "--session-id", newSessionID.uuidString.lowercased(),
            ]
        }

        if let model { arguments += ["--model", model] }
        if let effort { arguments += ["--effort", effort.rawValue] }

        if let permissionMode { arguments += ["--permission-mode", permissionMode.rawValue] }
        for directory in additionalDirectories {
            arguments += ["--add-dir", directory.path]
        }

        var environment = ProcessInfo.processInfo.environment

        environment["CLAUDE_CODE_ENTRYPOINT"] = "devspace"

        return ProcessTransport.Launch(
            executable: installation.executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment
        )
    }

    public static func capabilities(for installation: HarnessInstallation) -> HarnessCapabilities {
        HarnessCapabilities(
            routesPermissionRequests: true,
            canInterrupt: true,
            canSetPermissionMode: true,
            canSetModelInSession: false,
            canResumeSession: true,
            canForkSession: true
        )
    }
}
