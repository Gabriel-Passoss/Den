import Foundation
import Testing
import HarnessCore
@testable import Den

let claudeCodeID = HarnessID(rawValue: "claude-code")
let openCodeID = HarnessID(rawValue: "opencode")

/// How long an end-to-end wait tolerates: real processes start, so this is
/// generous, and it only runs out when something is actually wrong.
let processPatience: Duration = .seconds(10)

@MainActor
struct EndToEnd {
    let workspace: WorkspaceModel
    let claude: FakeCLI
    let openCode: FakeCLI
    let project: URL
    let attachments: URL

    fileprivate let environment: TestEnvironment
    fileprivate let opened = Opened()

    /// Opens a conversation the way the "Nova conversa" button does, and waits
    /// for its CLI to be up — killing it earlier would lose the launch record.
    func newChat(on harness: HarnessID = claudeCodeID) async throws -> ChatModel {
        let cli = harness == openCodeID ? openCode : claude
        let launched = cli.launches.count
        await workspace.newSession(harness: harness)
        await settle(within: processPatience) { cli.launches.count > launched }
        return try #require(workspace.active)
    }

    /// A second workspace over the same disk and defaults: what the next app
    /// launch sees.
    func relaunched() -> WorkspaceModel {
        let workspace = WorkspaceModel.live(environment)
        opened.workspaces.append(workspace)
        return workspace
    }
}

/// Every workspace a test opened, so their CLIs get stopped even when the
/// test throws halfway.
@MainActor
fileprivate final class Opened {
    var workspaces: [WorkspaceModel] = []
}

/// Runs `body` against the real harnesses, transport and transcript store,
/// with each CLI pinned to a `FakeCLI`. Nothing reaches a real CLI or the
/// user's own sessions.
@MainActor
func withEndToEnd(_ body: (EndToEnd) async throws -> Void) async throws {
    let scratch = ScratchDefaults()
    let defaults = scratch.defaults
    let root = FileManager.default.temporaryDirectory
        .appending(path: "DenTests-" + UUID().uuidString)
    let claude = try FakeCLI()
    let openCode = try FakeCLI()

    let environment = TestEnvironment(root: root, defaults: defaults,
                                      registry: HarnessRegistry.standard.pinning([
                                          claudeCodeID: claude.executable,
                                          openCodeID: openCode.executable,
                                      ]))
    let project = environment.workingDirectory
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    let workspace = WorkspaceModel.live(environment)

    defer {
        scratch.remove()
        try? FileManager.default.removeItem(at: root)
        claude.remove()
        openCode.remove()
    }

    let e2e = EndToEnd(workspace: workspace, claude: claude, openCode: openCode,
                       project: project, attachments: environment.attachmentsRoot,
                       environment: environment)
    e2e.opened.workspaces.append(workspace)
    var failure: (any Error)?
    do { try await body(e2e) } catch { failure = error }
    for opened in e2e.opened.workspaces { await opened.stopAll() }
    if let failure { throw failure }
}
