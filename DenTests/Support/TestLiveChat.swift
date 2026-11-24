import Foundation
import Testing
import HarnessCore
@testable import Den

@MainActor
struct LiveChatHarness {
    let chat: ChatModel
    let harness: FakeHarness
    let attachments: URL
    let store: FileTranscriptStore

    var session: FakeSession { harness.session }
    var log: HarnessLog { harness.log }
}

@MainActor
func withLiveChat(configure: (inout FakeHarness) -> Void = { _ in },
                  alongside others: [FakeHarness] = [],
                  runner: any CommandRunner = SystemCommandRunner(),
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
    chat.runner = runner
    try await body(LiveChatHarness(chat: chat, harness: harness,
                                   attachments: attachments, store: store))
}

@MainActor
func settle(within patience: Duration = .seconds(10),
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

func assistant(_ text: String) -> SessionUpdate {
    .entry(TranscriptEntry(timestamp: Date(), kind: .assistantText(text), raw: .null))
}

func endOfTurn(isError: Bool = false) -> SessionUpdate {
    .entry(TranscriptEntry(
        timestamp: Date(),
        kind: .turnResult(TurnResult(usage: .zero, stopReason: "end_turn", isError: isError)),
        raw: .null))
}

func routeQuestion(id: String) -> PermissionRequest {
    PermissionRequest(
        id: id, toolName: "AskUserQuestion",
        input: .object(["questions": .array([.object([
            "question": .string("Qual caminho?"),
            "header": .string("Rota"),
            "options": .array([.object(["label": .string("A")])]),
        ])])]))
}
