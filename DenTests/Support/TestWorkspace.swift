import Foundation
import HarnessCore
@testable import Den

@MainActor
struct WorkspaceHarness {
    let model: WorkspaceModel
    let defaults: UserDefaults
    let store: FileTranscriptStore
}

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
    let store = FileTranscriptStore(root: root)
    let model = WorkspaceModel(store: store, defaults: defaults,
                               cache: SessionCache(defaults: defaults),
                               attachmentsRoot: root.appending(path: "attachments"))
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
