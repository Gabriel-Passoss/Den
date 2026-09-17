import Testing
import Foundation
import HarnessCore
@testable import ClaudeHarness

private let install = HarnessInstallation(executable: "/opt/homebrew/bin/claude", version: "2.1.236")
private let cwd = URL(fileURLWithPath: "/tmp/scratch")
private let session = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
private let previousSession = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!

@Test func theLaunchCarriesTheFlagThatEnablesPermissionRouting() {
    let launch = ClaudeLaunch.make(installation: install, workingDirectory: cwd, session: .fresh(sessionID: session))
    let args = launch.arguments
    let i = try! #require(args.firstIndex(of: "--permission-prompt-tool"))
    #expect(args[args.index(after: i)] == "stdio")
}

@Test func theLaunchUsesTheStreamingProtocolInBothDirections() {
    let args = ClaudeLaunch.make(installation: install, workingDirectory: cwd, session: .fresh(sessionID: session)).arguments
    #expect(args.contains("-p"))
    for pair in [("--output-format", "stream-json"), ("--input-format", "stream-json")] {
        let i = try! #require(args.firstIndex(of: pair.0))
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

@Test func theEnvironmentAnnouncesDevSpaceAsTheEntrypoint() {
    let launch = ClaudeLaunch.make(installation: install, workingDirectory: cwd, session: .fresh(sessionID: session))
    #expect(launch.environment["CLAUDE_CODE_ENTRYPOINT"] == "devspace")
}

// MARK: - SessionStart

// `--resume <id>` alone already reuses the original session (`claude --help`
// documents `--fork-session` as what changes that). The three cases below
// pin, per case, exactly which flags come out — the two that matter most are
// that `.resume` emits no `--session-id` at all, and that `.fork` is the only
// case that emits `--fork-session`. A test that only checked `.contains` for
// each flag independently would pass even if `.resume` wrongly carried both
// `--resume` and `--session-id` — pinning absence, not just presence, is the
// point.

@Test func freshEmitsANewSessionIDAndNothingElseSessionRelated() {
    let args = ClaudeLaunch.make(installation: install, workingDirectory: cwd, session: .fresh(sessionID: session)).arguments
    let i = try! #require(args.firstIndex(of: "--session-id"))
    #expect(args[args.index(after: i)] == "11111111-2222-3333-4444-555555555555")
    #expect(!args.contains("--resume"))
    #expect(!args.contains("--fork-session"))
}

@Test func resumeReusesTheOriginalIDAndEmitsNoSessionIDFlag() {
    let args = ClaudeLaunch.make(installation: install, workingDirectory: cwd, session: .resume(harnessSessionID: previousSession)).arguments
    let i = try! #require(args.firstIndex(of: "--resume"))
    #expect(args[args.index(after: i)] == "99999999-8888-7777-6666-555555555555")
    // The assertion that matters most in this test: no --session-id at all.
    // Emitting one here is exactly the incoherent pair this type exists to
    // make unrepresentable — "use this new id" and "continue the old session
    // without forking" in the same argv.
    #expect(!args.contains("--session-id"))
    #expect(!args.contains("--fork-session"))
}

@Test func forkResumesTheOldIDMarksForkSessionAndCarriesTheNewID() {
    let args = ClaudeLaunch.make(
        installation: install, workingDirectory: cwd,
        session: .fork(from: previousSession, newSessionID: session)
    ).arguments
    let resumeIndex = try! #require(args.firstIndex(of: "--resume"))
    #expect(args[args.index(after: resumeIndex)] == "99999999-8888-7777-6666-555555555555")
    // The assertion that matters most in this test: --fork-session is
    // present. Without it, --resume plus a fresh --session-id is the same
    // incoherent pair the .fork case exists to distinguish from a plain
    // resume.
    #expect(args.contains("--fork-session"))
    let sessionIndex = try! #require(args.firstIndex(of: "--session-id"))
    #expect(args[args.index(after: sessionIndex)] == "11111111-2222-3333-4444-555555555555")
}

@Test func theLaunchPassesModelPermissionModeAndEachAdditionalDirectory() {
    let args = ClaudeLaunch.make(
        installation: install,
        workingDirectory: cwd,
        session: .fresh(sessionID: session),
        model: "claude-opus-4-6",
        permissionMode: "acceptEdits",
        additionalDirectories: [
            URL(fileURLWithPath: "/tmp/scratch/a"),
            URL(fileURLWithPath: "/tmp/scratch/b"),
        ]
    ).arguments

    let modelIndex = try! #require(args.firstIndex(of: "--model"))
    #expect(args[args.index(after: modelIndex)] == "claude-opus-4-6")

    let modeIndex = try! #require(args.firstIndex(of: "--permission-mode"))
    #expect(args[args.index(after: modeIndex)] == "acceptEdits")

    // --add-dir repeats once per entry, each immediately followed by its own path.
    let addDirIndices = args.indices.filter { args[$0] == "--add-dir" }
    #expect(addDirIndices.count == 2)
    #expect(addDirIndices.map { args[args.index(after: $0)] } == ["/tmp/scratch/a", "/tmp/scratch/b"])
}

@Test func claudeCodeDeclaresWhatItSupports() {
    let c = ClaudeLaunch.capabilities(for: install)
    #expect(c.routesPermissionRequests)
    #expect(c.canInterrupt)
    #expect(c.canSetPermissionMode)
    #expect(c.canResumeSession)
    #expect(c.canForkSession)
    // `set_model` exists in the control protocol (OutboundControlRequest),
    // so flipping this to `true` looks like fixing an oversight. It isn't:
    // it was never verified against the real CLI, and spec §4.1 wants the
    // conservative answer until someone confirms it. Only change this to
    // `true` once a real session has shown the CLI accepting a `set_model`
    // control request and actually acting on it — not before.
    #expect(!c.canSetModelInSession)
}
