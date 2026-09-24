import Foundation
import HarnessCore
@testable import DevSpace

@MainActor
struct WorkspaceHarness {
    let model: WorkspaceModel
    let defaults: UserDefaults
    let store: FileTranscriptStore
}

/// Builds a WorkspaceModel on a throwaway defaults suite and a throwaway store
/// root. `seed` runs before the model exists, so it can plant legacy keys for
/// the migration that happens in init.
@MainActor
func withWorkspace(seed: (UserDefaults) -> Void = { _ in },
                   _ body: (WorkspaceHarness) async throws -> Void) async throws {
    let suite = "DevSpaceTests." + UUID().uuidString
    guard let defaults = UserDefaults(suiteName: suite) else {
        fatalError("could not create suite \(suite)")
    }
    let root = FileManager.default.temporaryDirectory
        .appending(path: "DevSpaceTests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    seed(defaults)
    let store = FileTranscriptStore(root: root)
    let model = WorkspaceModel(store: store, defaults: defaults,
                               cache: SessionCache(defaults: defaults))
    try await body(WorkspaceHarness(model: model, defaults: defaults, store: store))
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
