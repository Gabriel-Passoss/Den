import Foundation
import Testing
import HarnessCore
@testable import Den

nonisolated let claudeCodeID = HarnessID(rawValue: "claude-code")
nonisolated let openCodeID = HarnessID(rawValue: "opencode")

let processPatience: Duration = .seconds(10)

@MainActor
func refresh(_ workspace: WorkspaceModel, until reached: @MainActor () -> Bool) async {
    let deadline = ContinuousClock.now + processPatience
    while ContinuousClock.now < deadline {
        await workspace.refresh()
        if reached() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor
struct EndToEnd {
    let workspace: WorkspaceModel
    let claude: FakeCLI
    let openCode: FakeCLI
    let project: URL
    let attachments: URL

    fileprivate let environment: TestEnvironment
    fileprivate let opened = Opened()

    func newChat(on harness: HarnessID = claudeCodeID) async throws -> ChatModel {
        let cli = harness == openCodeID ? openCode : claude
        let launched = cli.launches.count
        await workspace.newSession(harness: harness)
        await settle(within: processPatience) { cli.launches.count > launched }
        return try #require(workspace.active)
    }

    func relaunched() -> WorkspaceModel {
        let workspace = WorkspaceModel.live(environment)
        opened.workspaces.append(workspace)
        return workspace
    }
}

@MainActor
private final class Opened {
    var workspaces: [WorkspaceModel] = []
}

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
