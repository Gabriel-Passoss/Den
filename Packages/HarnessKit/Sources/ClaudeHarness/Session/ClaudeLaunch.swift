import Foundation
import HarnessCore

public enum ClaudeSessionStart: Sendable, Equatable {

    case fresh(sessionID: UUID)

    case resume(harnessSessionID: UUID)

    case fork(from: UUID, newSessionID: UUID)

    public init(_ start: SessionStart) {
        switch start {
        case .fresh:
            self = .fresh(sessionID: UUID())
        case .resume(let harnessSessionID):

            guard let known = UUID(uuidString: harnessSessionID) else {
                self = .fresh(sessionID: UUID())
                return
            }
            self = .resume(harnessSessionID: known)
        case .fork(let from):
            guard let known = UUID(uuidString: from) else {
                self = .fresh(sessionID: UUID())
                return
            }
            self = .fork(from: known, newSessionID: UUID())
        }
    }

    public var harnessSessionID: String {
        switch self {
        case .fresh(let id): id.uuidString.lowercased()
        case .resume(let id): id.uuidString.lowercased()
        case .fork(_, let id): id.uuidString.lowercased()
        }
    }
}

public enum EffortLevel: String, Sendable, Equatable, CaseIterable {
    case low, medium, high, xhigh, max
}

public enum ClaudeLaunch {
    public static func make(
        installation: HarnessInstallation,
        workingDirectory: URL,
        session: ClaudeSessionStart,
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

        environment["CLAUDE_CODE_ENTRYPOINT"] = "den"

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
