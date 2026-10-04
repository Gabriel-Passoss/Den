import Testing
import Foundation
import HarnessCore
import HarnessTestSupport
@testable import ClaudeHarness

private let install = HarnessInstallation(executable: "/opt/homebrew/bin/claude", version: "2.1.236")
private let cwd = URL(fileURLWithPath: "/tmp/scratch")
private let session = fixedUUID("11111111-2222-3333-4444-555555555555")
private let previousSession = fixedUUID("99999999-8888-7777-6666-555555555555")

@Test func theLaunchCarriesTheFlagThatEnablesPermissionRouting() throws {
    let launch = ClaudeLaunch.make(installation: install, workingDirectory: cwd, session: .fresh(sessionID: session))
    let args = launch.arguments
    let i = try #require(args.firstIndex(of: "--permission-prompt-tool"))
    #expect(args[args.index(after: i)] == "stdio")
}

@Test func theLaunchUsesTheStreamingProtocolInBothDirections() throws {
    let args = ClaudeLaunch.make(installation: install, workingDirectory: cwd, session: .fresh(sessionID: session)).arguments
    #expect(args.contains("-p"))
    for pair in [("--output-format", "stream-json"), ("--input-format", "stream-json")] {
        let i = try #require(args.firstIndex(of: pair.0))
        #expect(args[args.index(after: i)] == pair.1)
    }
    #expect(args.contains("--verbose"))
    #expect(args.contains("--include-partial-messages"))
}

@Test func theLaunchRunsInTheRequestedDirectory() {
    let launch = ClaudeLaunch.make(installation: install, workingDirectory: cwd, session: .fresh(sessionID: session))
    #expect(launch.workingDirectory == cwd)
    #expect(launch.executable == "/opt/homebrew/bin/claude")
}

@Test func theEnvironmentAnnouncesDenAsTheEntrypoint() {
    let launch = ClaudeLaunch.make(installation: install, workingDirectory: cwd, session: .fresh(sessionID: session))
    #expect(launch.environment["CLAUDE_CODE_ENTRYPOINT"] == "den")
}

// MARK: - SessionStart

@Test func freshEmitsANewSessionIDAndNothingElseSessionRelated() throws {
    let args = ClaudeLaunch.make(installation: install, workingDirectory: cwd, session: .fresh(sessionID: session)).arguments
    let i = try #require(args.firstIndex(of: "--session-id"))
    #expect(args[args.index(after: i)] == "11111111-2222-3333-4444-555555555555")
    #expect(!args.contains("--resume"))
    #expect(!args.contains("--fork-session"))
}

@Test func resumeReusesTheOriginalIDAndEmitsNoSessionIDFlag() throws {
    let args = ClaudeLaunch.make(installation: install, workingDirectory: cwd, session: .resume(harnessSessionID: previousSession)).arguments
    let i = try #require(args.firstIndex(of: "--resume"))
    #expect(args[args.index(after: i)] == "99999999-8888-7777-6666-555555555555")

    #expect(!args.contains("--session-id"))
    #expect(!args.contains("--fork-session"))
}

@Test func forkResumesTheOldIDMarksForkSessionAndCarriesTheNewID() throws {
    let args = ClaudeLaunch.make(
        installation: install, workingDirectory: cwd,
        session: .fork(from: previousSession, newSessionID: session)
    ).arguments
    let resumeIndex = try #require(args.firstIndex(of: "--resume"))
    #expect(args[args.index(after: resumeIndex)] == "99999999-8888-7777-6666-555555555555")

    #expect(args.contains("--fork-session"))
    let sessionIndex = try #require(args.firstIndex(of: "--session-id"))
    #expect(args[args.index(after: sessionIndex)] == "11111111-2222-3333-4444-555555555555")
}

@Test func theLaunchPassesModelPermissionModeAndEachAdditionalDirectory() throws {
    let args = ClaudeLaunch.make(
        installation: install,
        workingDirectory: cwd,
        session: .fresh(sessionID: session),
        model: "claude-opus-4-6",
        permissionMode: .acceptEdits,
        additionalDirectories: [
            URL(fileURLWithPath: "/tmp/scratch/a"),
            URL(fileURLWithPath: "/tmp/scratch/b"),
        ]
    ).arguments

    let modelIndex = try #require(args.firstIndex(of: "--model"))
    #expect(args[args.index(after: modelIndex)] == "claude-opus-4-6")

    let modeIndex = try #require(args.firstIndex(of: "--permission-mode"))
    #expect(args[args.index(after: modeIndex)] == "acceptEdits")

    let addDirIndices = args.indices.filter { args[$0] == "--add-dir" }
    #expect(addDirIndices.count == 2)
    #expect(addDirIndices.map { args[args.index(after: $0)] } == ["/tmp/scratch/a", "/tmp/scratch/b"])
}

@Test func theLaunchPassesTheEffortLevel() throws {
    let args = ClaudeLaunch.make(
        installation: install,
        workingDirectory: cwd,
        session: .fresh(sessionID: session),
        effort: .xhigh
    ).arguments
    let i = try #require(args.firstIndex(of: "--effort"))
    #expect(args[args.index(after: i)] == "xhigh")
}

@Test func withoutAnEffortTheFlagIsAbsent() {
    let args = ClaudeLaunch.make(
        installation: install, workingDirectory: cwd, session: .fresh(sessionID: session)
    ).arguments
    #expect(!args.contains("--effort"))
}

@Test func everyPermissionModeReachesTheCLIWithItsVerifiedSpelling() throws {
    let spellings = try PermissionMode.allCases.map { mode -> String in
        let args = ClaudeLaunch.make(
            installation: install,
            workingDirectory: cwd,
            session: .fresh(sessionID: session),
            permissionMode: mode
        ).arguments
        let index = try #require(args.firstIndex(of: "--permission-mode"))
        return args[args.index(after: index)]
    }
    #expect(spellings == ["acceptEdits", "auto", "bypassPermissions", "manual", "dontAsk", "plan"])
}

@Test func theProbesPermissionSessionAsksInsteadOfDeciding() throws {
    let args = ClaudeLaunch.make(
        installation: install,
        workingDirectory: cwd,
        session: .fresh(sessionID: session),
        permissionMode: .manual
    ).arguments

    let promptToolIndex = try #require(args.firstIndex(of: "--permission-prompt-tool"))
    #expect(args[args.index(after: promptToolIndex)] == "stdio")

    let modeIndex = try #require(args.firstIndex(of: "--permission-mode"))
    #expect(args[args.index(after: modeIndex)] == "manual")

    #expect(args.contains("--input-format"))
    #expect(args.contains("--output-format"))

    #expect(!args.contains("--safe-mode"))
}

@Test func noPermissionModeMeansNoFlagAtAll() {
    let args = ClaudeLaunch.make(
        installation: install,
        workingDirectory: cwd,
        session: .fresh(sessionID: session)
    ).arguments
    #expect(!args.contains("--permission-mode"))
}

@Test func claudeCodeDeclaresWhatItSupports() {
    let c = ClaudeLaunch.capabilities(for: install)
    #expect(c.routesPermissionRequests)
    #expect(c.canInterrupt)
    #expect(c.canSetPermissionMode)
    #expect(c.canResumeSession)
    #expect(c.canForkSession)

    #expect(!c.canSetModelInSession)
}
