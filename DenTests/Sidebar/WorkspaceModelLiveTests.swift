import Testing
import Foundation
import HarnessCore
import DenStore
@testable import Den

@Test func liveBuildsTheWorkspaceOnTheEnvironmentItIsGiven() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "DenTests-" + UUID().uuidString)
    let scratch = ScratchDefaults()
    defer {
        scratch.remove()
        try? FileManager.default.removeItem(at: root)
    }
    let openCode = try #require(HarnessRegistry.standard.harness(for: openCodeID))
    let environment = TestEnvironment(root: root, defaults: scratch.defaults,
                                      registry: HarnessRegistry(harnesses: [openCode]))

    let repositories = try DenStore.open(at: environment.databaseFile).repositories

    let workspace = WorkspaceModel.live(environment, repositories: repositories)

    #expect(workspace.workingDirectory == environment.workingDirectory)
    #expect(workspace.availableHarnesses == [openCodeID])

    try await repositories.sessions.saveMetadata(storedSession("Guardada"))
    await workspace.refresh()
    #expect(workspace.summaries.map(\.title) == ["Guardada"])

    workspace.addFolder()
    let reopened = WorkspaceModel(store: repositories.sessions, sidebar: repositories.sidebar,
                                  defaults: environment.defaults,
                                  cache: SessionCache(defaults: environment.defaults))
    #expect(reopened.folders.count == 1)
}
