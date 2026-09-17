import Testing
import Foundation
import HarnessCore
@testable import ClaudeHarness

private let install = HarnessInstallation(executable: "/opt/homebrew/bin/claude", version: "2.1.236")
private let cwd = URL(fileURLWithPath: "/tmp/scratch")
private let session = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

@Test func theLaunchCarriesTheFlagThatEnablesPermissionRouting() {
    let launch = ClaudeLaunch.make(installation: install, workingDirectory: cwd, sessionID: session)
    let args = launch.arguments
    let i = try! #require(args.firstIndex(of: "--permission-prompt-tool"))
    #expect(args[args.index(after: i)] == "stdio")
}

@Test func theLaunchUsesTheStreamingProtocolInBothDirections() {
    let args = ClaudeLaunch.make(installation: install, workingDirectory: cwd, sessionID: session).arguments
    #expect(args.contains("-p"))
    for pair in [("--output-format", "stream-json"), ("--input-format", "stream-json")] {
        let i = try! #require(args.firstIndex(of: pair.0))
        #expect(args[args.index(after: i)] == pair.1)
    }
    #expect(args.contains("--verbose"))
    #expect(args.contains("--include-partial-messages"))
}

@Test func theSessionIDIsOursAndLowercased() {
    let args = ClaudeLaunch.make(installation: install, workingDirectory: cwd, sessionID: session).arguments
    let i = try! #require(args.firstIndex(of: "--session-id"))
    #expect(args[args.index(after: i)] == "11111111-2222-3333-4444-555555555555")
}

@Test func resumingPassesTheHarnessSessionID() {
    let previous = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!
    let args = ClaudeLaunch.make(installation: install, workingDirectory: cwd,
                                 sessionID: session, resuming: previous).arguments
    let i = try! #require(args.firstIndex(of: "--resume"))
    #expect(args[args.index(after: i)] == "99999999-8888-7777-6666-555555555555")
}

@Test func notResumingOmitsTheFlagEntirely() {
    let args = ClaudeLaunch.make(installation: install, workingDirectory: cwd, sessionID: session).arguments
    #expect(!args.contains("--resume"))
}

@Test func theLaunchRunsInTheRequestedDirectory() {
    let launch = ClaudeLaunch.make(installation: install, workingDirectory: cwd, sessionID: session)
    #expect(launch.workingDirectory == cwd)
    #expect(launch.executable == "/opt/homebrew/bin/claude")
}

@Test func theEnvironmentAnnouncesDevSpaceAsTheEntrypoint() {
    let launch = ClaudeLaunch.make(installation: install, workingDirectory: cwd, sessionID: session)
    #expect(launch.environment["CLAUDE_CODE_ENTRYPOINT"] == "devspace")
}

@Test func claudeCodeDeclaresWhatItSupports() {
    let c = ClaudeLaunch.capabilities(for: install)
    #expect(c.routesPermissionRequests)
    #expect(c.canInterrupt)
    #expect(c.canSetPermissionMode)
    #expect(c.canResumeSession)
    #expect(c.canForkSession)
}
