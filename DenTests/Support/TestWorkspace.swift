import Foundation
import HarnessCore
import DenStore
@testable import Den

@MainActor
struct WorkspaceHarness {
    let model: WorkspaceModel
    let defaults: UserDefaults
    let repositories: Repositories

    var store: any SessionRepository { repositories.sessions }

    func reopened() -> WorkspaceModel {
        WorkspaceModel(store: repositories.sessions, defaults: defaults,
                       cache: SessionCache(defaults: defaults))
    }
}

/// Builds a WorkspaceModel on a throwaway defaults suite and a throwaway store
/// root. `seed` runs before the model exists, so it can plant legacy keys for
/// the migration that happens in init.
@MainActor
func withWorkspace(seed: (UserDefaults) -> Void = { _ in },
                   _ body: (WorkspaceHarness) async throws -> Void) async throws {
    let scratch = ScratchDefaults()
    let defaults = scratch.defaults
    let root = FileManager.default.temporaryDirectory
        .appending(path: "DenTests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        scratch.remove()
        try? FileManager.default.removeItem(at: root)
    }

    seed(defaults)
    let repositories = scratchRepositories()
    let model = WorkspaceModel(store: repositories.sessions, defaults: defaults,
                               cache: SessionCache(defaults: defaults),
                               attachmentsRoot: root.appending(path: "attachments"))
    try await body(WorkspaceHarness(model: model, defaults: defaults, repositories: repositories))
}

func summary(_ title: String, in directory: String = "/code/project",
             updated: TimeInterval = 0, id: UUID = UUID()) -> SessionSummary {
    SessionSummary(id: id, title: title,
                   workingDirectory: URL(fileURLWithPath: directory),
                   harnesses: [], usage: .zero, entryCount: 0,
                   updatedAt: Date(timeIntervalSince1970: updated))
}

func storedSession(_ title: String, in directory: String = "/code/project") -> Session {
    Session(title: title, workingDirectory: URL(fileURLWithPath: directory),
            segments: [Segment(harness: HarnessID(rawValue: "test-harness"),
                               harnessSessionID: "", model: "")])
}
