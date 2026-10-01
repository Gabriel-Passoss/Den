import Foundation
import Testing
import HarnessCore
@testable import Den

@MainActor
struct LiveChatHarness {
    let chat: ChatModel
    let harness: FakeHarness
    let others: [FakeHarness]
    let attachments: URL
    let store: FileTranscriptStore

    var session: FakeSession { harness.session }
    var log: HarnessLog { harness.log }
}

/// Builds a ChatModel whose registry contains only fakes, so nothing reaches a
/// real CLI. `configure` runs before the registry is built.
@MainActor
func withLiveChat(configure: (inout FakeHarness) -> Void = { _ in },
                  alongside others: [FakeHarness] = [],
                  _ body: (LiveChatHarness) async throws -> Void) async throws {
    var harness = FakeHarness()
    configure(&harness)

    let scratch = ScratchDefaults()
    let defaults = scratch.defaults
    let root = FileManager.default.temporaryDirectory
        .appending(path: "DenTests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        scratch.remove()
        try? FileManager.default.removeItem(at: root)
    }

    let attachments = root.appending(path: "attachments")
    let store = FileTranscriptStore(root: root)
    let chat = ChatModel(store: store,
                         workingDirectory: root,
                         harness: harness.id,
                         cache: SessionCache(defaults: defaults),
                         registry: HarnessRegistry(harnesses: [harness] + others),
                         attachmentsRoot: attachments)
    try await body(LiveChatHarness(chat: chat, harness: harness, others: others,
                                   attachments: attachments, store: store))
}

/// The update stream is consumed by a detached task, so assertions about events
/// have to wait for it rather than read straight after emitting. Running out of
/// patience is a failure, not a quiet return — otherwise the wait reads like an
/// assertion while proving nothing.
@MainActor
func settle(within patience: Duration = .seconds(1),
            until reached: @MainActor () -> Bool,
            sourceLocation: SourceLocation = #_sourceLocation) async {
    let deadline = ContinuousClock.now + patience
    while ContinuousClock.now < deadline {
        if reached() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
    if reached() { return }
    Issue.record("the stream never reached the expected state",
                 sourceLocation: sourceLocation)
}
