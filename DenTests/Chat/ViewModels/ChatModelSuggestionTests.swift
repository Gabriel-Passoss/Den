import Testing
import Foundation
import HarnessCore
@testable import Den

private let suggestion = "Sim, inclua a rotação."

private func assistant(_ text: String) -> SessionUpdate {
    .entry(TranscriptEntry(timestamp: Date(), kind: .assistantText(text), raw: .null))
}

private func endOfTurn(isError: Bool = false) -> SessionUpdate {
    .entry(TranscriptEntry(
        timestamp: Date(),
        kind: .turnResult(TurnResult(usage: .zero, stopReason: "end_turn", isError: isError)),
        raw: .null))
}

private func suggestionCalls(_ runner: FakeCommandRunner) async -> [FakeCommandRunner.Call] {
    let calls = await runner.calls
    return calls.filter { $0.arguments.last?.contains(ReplySuggestion.none) == true }
}

private func waitForSuggestionCalls(_ runner: FakeCommandRunner, count: Int = 1) async {
    for _ in 0..<400 {
        if await suggestionCalls(runner).count >= count { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("the quick prompt for a suggestion never ran")
}

private func expectNoSuggestionCall(_ runner: FakeCommandRunner,
                                    sourceLocation: SourceLocation = #_sourceLocation) async {
    try? await Task.sleep(for: .milliseconds(200))
    #expect(await suggestionCalls(runner).isEmpty, sourceLocation: sourceLocation)
}

private func finishTurn(_ live: LiveChatHarness, request: String = "crie um backup",
                        reply: String = "Quer que eu inclua a rotação?",
                        isError: Bool = false) async {
    await live.chat.send(text: request)
    await live.session.emit(assistant(reply))
    await live.session.emit(endOfTurn(isError: isError))
    await settle { !live.chat.isBusy }
}

private func withSuggestingChat(_ runner: FakeCommandRunner,
                                _ body: (LiveChatHarness) async throws -> Void) async throws {
    try await withLiveChat(configure: { $0.quickPrompt = ["one-shot"] }, runner: runner, body)
}

private func suggested(_ live: LiveChatHarness, _ runner: FakeCommandRunner) async {
    await runner.answer(with: suggestion)
    await finishTurn(live)
    await settle { live.chat.suggestedReply != nil }
}

@Test func theTitleComesFromTheHarnessQuickPrompt() async throws {
    let runner = FakeCommandRunner()
    await runner.answer(with: "Backup dos projetos")
    try await withLiveChat(configure: { $0.quickPrompt = ["one-shot"] }, runner: runner) { live in
        await live.chat.send(text: "crie um script de backup")

        await settle { live.chat.title == "Backup dos projetos" }
        let call = try #require(await runner.calls.first)
        #expect(call.executable == "/fake/bin/harness")
        #expect(call.arguments.first == "one-shot")
        #expect(call.arguments.last?.contains("crie um script de backup") == true)
    }
}

@Test func aQuestionAtTheEndOfATurnBecomesASuggestedReply() async throws {
    let runner = FakeCommandRunner()
    try await withSuggestingChat(runner) { live in
        await suggested(live, runner)

        #expect(live.chat.suggestedReply == suggestion)
        #expect(live.chat.visibleSuggestion == suggestion)
        let call = try #require(await suggestionCalls(runner).first)
        #expect(call.arguments.first == "one-shot")
        #expect(call.arguments.last?.contains("Pedido do usuário: crie um backup") == true)
        #expect(call.arguments.last?.contains("Quer que eu inclua a rotação?") == true)
    }
}

@Test func aReplyWithoutAQuestionSuggestsNothing() async throws {
    let runner = FakeCommandRunner()
    try await withSuggestingChat(runner) { live in
        await finishTurn(live, reply: "Feito. Os testes passaram.")
        await expectNoSuggestionCall(runner)
        #expect(live.chat.suggestedReply == nil)
    }
}

@Test func aFailedTurnSuggestsNothing() async throws {
    let runner = FakeCommandRunner()
    try await withSuggestingChat(runner) { live in
        await finishTurn(live, isError: true)
        await expectNoSuggestionCall(runner)
    }
}

@Test func aPendingPermissionSuggestsNothing() async throws {
    let runner = FakeCommandRunner()
    try await withSuggestingChat(runner) { live in
        await live.chat.send(text: "crie um backup")
        await live.session.emit(assistant("Quer que eu inclua a rotação?"))
        await live.session.emit(.permission(PermissionRequest(id: "p-1", toolName: "Write")))
        await settle { live.chat.pending != nil }
        await live.session.emit(endOfTurn())
        await settle { !live.chat.isBusy }

        await expectNoSuggestionCall(runner)
    }
}

@Test func aPendingQuestionCardSuggestsNothing() async throws {
    let prompt = try #require(QuestionPrompt(from: PermissionRequest(
        id: "q-1", toolName: "AskUserQuestion",
        input: .object(["questions": .array([.object([
            "question": .string("Qual caminho?"),
            "header": .string("Rota"),
            "options": .array([.object(["label": .string("A")])]),
        ])])]))))
    let runner = FakeCommandRunner()
    try await withSuggestingChat(runner) { live in
        await live.chat.send(text: "crie um backup")
        await live.session.emit(assistant("Quer que eu inclua a rotação?"))
        live.chat.pendingQuestion = prompt
        await live.session.emit(endOfTurn())
        await settle { !live.chat.isBusy }

        await expectNoSuggestionCall(runner)
    }
}

@Test func aHarnessWithoutAQuickPromptSuggestsNothing() async throws {
    let runner = FakeCommandRunner()
    try await withLiveChat(runner: runner) { live in
        await finishTurn(live)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(await runner.calls.isEmpty)
        #expect(live.chat.suggestedReply == nil)
    }
}

@Test func aTurnWithoutTextOfItsOwnSuggestsNothing() async throws {
    let runner = FakeCommandRunner()
    try await withSuggestingChat(runner) { live in
        await suggested(live, runner)

        await live.chat.send(text: "sim")
        await live.session.emit(endOfTurn())
        await settle { !live.chat.isBusy }

        try? await Task.sleep(for: .milliseconds(200))
        #expect(await suggestionCalls(runner).count == 1)
        #expect(live.chat.suggestedReply == nil)
    }
}

@Test func aRestoredConversationEndingInAQuestionSuggestsNothing() async throws {
    let runner = FakeCommandRunner()
    var harness = FakeHarness()
    harness.quickPrompt = ["one-shot"]
    let root = FileManager.default.temporaryDirectory
        .appending(path: "DenTests-" + UUID().uuidString)
    let segment = Segment(harness: harness.id, harnessSessionID: "", model: "", entries: [
        TranscriptEntry(timestamp: Date(),
                        kind: .userMessage(text: "crie um backup", attachments: []), raw: .null),
        TranscriptEntry(timestamp: Date(),
                        kind: .assistantText("Quer que eu inclua a rotação?"), raw: .null),
        TranscriptEntry(timestamp: Date(),
                        kind: .turnResult(TurnResult(usage: .zero, stopReason: "end_turn",
                                                     isError: false)), raw: .null),
    ])
    let chat = ChatModel(store: FileTranscriptStore(root: root),
                         restoring: Session(title: "restored", workingDirectory: root,
                                            segments: [segment]),
                         cache: scratchCache,
                         registry: HarnessRegistry(harnesses: [harness]),
                         runner: runner)

    try? await Task.sleep(for: .milliseconds(200))
    #expect(await runner.calls.isEmpty)
    #expect(chat.suggestedReply == nil)
}

@Test func aSuggestionArrivingAfterTheUserRepliedIsDropped() async throws {
    let runner = FakeCommandRunner()
    try await withSuggestingChat(runner) { live in
        await runner.answer(with: suggestion)
        await runner.hold()
        await finishTurn(live)
        await waitForSuggestionCalls(runner)

        await live.chat.send(text: "não, sem rotação")
        await runner.release()

        try? await Task.sleep(for: .milliseconds(200))
        #expect(live.chat.suggestedReply == nil)
    }
}

@Test func dismissingWhileInFlightDropsTheLateSuggestion() async throws {
    let runner = FakeCommandRunner()
    try await withSuggestingChat(runner) { live in
        await runner.answer(with: suggestion)
        await runner.hold()
        await finishTurn(live)
        await waitForSuggestionCalls(runner)

        live.chat.dismissSuggestion()
        await runner.release()

        try? await Task.sleep(for: .milliseconds(200))
        #expect(live.chat.suggestedReply == nil)
    }
}

@Test func aFailingQuickPromptLeavesNoSuggestionAndNoNotice() async throws {
    let runner = FakeCommandRunner()
    try await withSuggestingChat(runner) { live in
        await runner.fail(HarnessFailure(reason: "claude missing"))
        await finishTurn(live)
        await waitForSuggestionCalls(runner)

        try? await Task.sleep(for: .milliseconds(200))
        #expect(live.chat.suggestedReply == nil)
        #expect(live.chat.lines.filter { $0.role == .notice }.isEmpty)
    }
}

@Test func theNoneMarkerLeavesNoSuggestion() async throws {
    let runner = FakeCommandRunner()
    try await withSuggestingChat(runner) { live in
        await runner.answer(with: "NENHUMA")
        await finishTurn(live)
        await waitForSuggestionCalls(runner)

        try? await Task.sleep(for: .milliseconds(200))
        #expect(live.chat.suggestedReply == nil)
    }
}

@Test func acceptingSendsTheSuggestionAsTheUsersReply() async throws {
    let runner = FakeCommandRunner()
    try await withSuggestingChat(runner) { live in
        await suggested(live, runner)

        await live.chat.acceptSuggestion()

        #expect(await live.session.sent.map(\.text).last == suggestion)
        #expect(live.chat.lines.last { $0.role == .user }?.text == suggestion)
        #expect(live.chat.suggestedReply == nil)
    }
}

@Test func acceptingTwiceSendsOnce() async throws {
    let runner = FakeCommandRunner()
    try await withSuggestingChat(runner) { live in
        await suggested(live, runner)

        let first = Task { await live.chat.acceptSuggestion() }
        let second = Task { await live.chat.acceptSuggestion() }
        await first.value
        await second.value

        #expect(await live.session.sent.filter { $0.text == suggestion }.count == 1)
    }
}

@Test func dismissingClearsWithoutSending() async throws {
    let runner = FakeCommandRunner()
    try await withSuggestingChat(runner) { live in
        await suggested(live, runner)
        let sentBefore = await live.session.sent.count

        live.chat.dismissSuggestion()

        #expect(live.chat.suggestedReply == nil)
        #expect(live.chat.visibleSuggestion == nil)
        #expect(await live.session.sent.count == sentBefore)
    }
}

@Test func typingHidesTheSuggestionAndClearingBringsItBack() async throws {
    let runner = FakeCommandRunner()
    try await withSuggestingChat(runner) { live in
        await suggested(live, runner)

        live.chat.prompt = "n"
        #expect(live.chat.visibleSuggestion == nil)
        #expect(live.chat.suggestedReply == suggestion)

        live.chat.prompt = ""
        #expect(live.chat.visibleSuggestion == suggestion)
    }
}

@Test func aPendingAttachmentHidesTheSuggestion() async throws {
    let runner = FakeCommandRunner()
    try await withSuggestingChat(runner) { live in
        await suggested(live, runner)

        live.chat.attach(imageData: Data([0x89, 0x50]))

        #expect(live.chat.visibleSuggestion == nil)
    }
}

@Test func aNewTurnStartingClearsTheSuggestion() async throws {
    let runner = FakeCommandRunner()
    try await withSuggestingChat(runner) { live in
        await suggested(live, runner)

        await live.session.emit(.event(.turnStarted))

        await settle { live.chat.suggestedReply == nil }
    }
}

@Test func stoppingClearsTheSuggestion() async throws {
    let runner = FakeCommandRunner()
    try await withSuggestingChat(runner) { live in
        await suggested(live, runner)

        await live.chat.stop()

        #expect(live.chat.suggestedReply == nil)
    }
}
