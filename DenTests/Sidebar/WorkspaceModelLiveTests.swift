import Testing
import Foundation
import HarnessCore
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

    let workspace = WorkspaceModel.live(environment)

    #expect(FileManager.default.fileExists(atPath: environment.sessionsRoot.path))
    #expect(workspace.workingDirectory == environment.workingDirectory)
    #expect(workspace.availableHarnesses == [openCodeID])

    try await FileTranscriptStore(root: environment.sessionsRoot)
        .saveMetadata(storedSession("Guardada"))
    await workspace.refresh()
    #expect(workspace.summaries.map(\.title) == ["Guardada"])

    workspace.addFolder()
    let reopened = WorkspaceModel(store: FileTranscriptStore(root: environment.sessionsRoot),
                                  defaults: environment.defaults,
                                  cache: SessionCache(defaults: environment.defaults))
    #expect(reopened.folders.count == 1)
}
