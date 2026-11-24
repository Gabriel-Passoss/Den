import Testing
import Foundation
import HarnessCore
@testable import Den

private let suggestion = "Sim, inclua a rotação."

private func withSuggestingChat(quickPrompt: [String]? = ["one-shot"],
                                _ body: (LiveChatHarness, FakeCommandRunner) async throws -> Void)
async throws {
    let runner = FakeCommandRunner()
    let configure: (inout FakeHarness) -> Void = { $0.quickPrompt = quickPrompt }
    try await withLiveChat(configure: configure, runner: runner) { live in
        try await body(live, runner)
    }
}

private func suggestionCalls(_ runner: FakeCommandRunner) async -> [FakeCommandRunner.Call] {
    let calls = await runner.calls
    return calls.filter { $0.arguments.last?.contains(ReplySuggestion.noQuestion) == true }
}

private func waitForSuggestionCall(_ runner: FakeCommandRunner) async {
    for _ in 0..<400 {
        if await !suggestionCalls(runner).isEmpty { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("the quick prompt for a suggestion never ran")
}

private func expectNoSuggestionCall(_ runner: FakeCommandRunner,
                                    sourceLocation: SourceLocation = #_sourceLocation) async {
    try? await Task.sleep(for: .milliseconds(200))
    #expect(await suggestionCalls(runner).isEmpty, sourceLocation: sourceLocation)
}

private func expectNoSuggestion(_ live: LiveChatHarness,
                                sourceLocation: SourceLocation = #_sourceLocation) async {
    try? await Task.sleep(for: .milliseconds(200))
    #expect(live.chat.suggestedReply == nil, sourceLocation: sourceLocation)
}

private func finishTurn(_ live: LiveChatHarness, request: String = "crie um backup",
                        reply: String = "Quer que eu inclua a rotação?",
                        isError: Bool = false,
                        beforeEnd: () async -> Void = {}) async {
    await live.chat.send(text: request)
    await live.session.emit(assistant(reply))
    await beforeEnd()
    await live.session.emit(endOfTurn(isError: isError))
    await settle { !live.chat.isBusy }
}

private func suggested(_ live: LiveChatHarness, _ runner: FakeCommandRunner) async {
    await runner.answer(with: suggestion)
    await finishTurn(live)
    await settle { live.chat.suggestedReply != nil }
}

@Test func theTitleComesFromTheHarnessQuickPrompt() async throws {
    try await withSuggestingChat { live, runner in
        await runner.answer(with: "Backup dos projetos")
        await live.chat.send(text: "crie um script de backup")

        await settle { live.chat.title == "Backup dos projetos" }
        let call = try #require(await runner.calls.first)
        #expect(call.executable == "/fake/bin/harness")
        #expect(call.arguments.first == "one-shot")
        #expect(call.arguments.last?.contains("crie um script de backup") == true)
    }
}

@Test func aQuestionAtTheEndOfATurnBecomesASuggestedReply() async throws {
    try await withSuggestingChat { live, runner in
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
    try await withSuggestingChat { live, runner in
        await finishTurn(live, reply: "Feito. Os testes passaram.")
        await expectNoSuggestionCall(runner)
    }
}

@Test func aFailedTurnSuggestsNothing() async throws {
    try await withSuggestingChat { live, runner in
        await finishTurn(live, isError: true)
        await expectNoSuggestionCall(runner)
    }
}

@Test func aPendingPermissionSuggestsNothing() async throws {
    try await withSuggestingChat { live, runner in
        await finishTurn(live) {
            await live.session.emit(.permission(PermissionRequest(id: "p-1", toolName: "Write")))
            await settle { live.chat.pending != nil }
        }
        await expectNoSuggestionCall(runner)
    }
}

@Test func aPendingQuestionCardSuggestsNothing() async throws {
    let prompt = try #require(QuestionPrompt(from: routeQuestion(id: "q-1")))
    try await withSuggestingChat { live, runner in
        await finishTurn(live) { live.chat.pendingQuestion = prompt }
        await expectNoSuggestionCall(runner)
    }
}

@Test func aHarnessWithoutAQuickPromptSuggestsNothing() async throws {
    try await withSuggestingChat(quickPrompt: nil) { live, runner in
        await finishTurn(live)
        await expectNoSuggestion(live)
        #expect(await runner.calls.isEmpty)
    }
}

@Test func aTurnWithoutTextOfItsOwnSuggestsNothing() async throws {
    try await withSuggestingChat { live, runner in
        await suggested(live, runner)

        await live.chat.send(text: "sim")
        await live.session.emit(endOfTurn())
        await settle { !live.chat.isBusy }

        await expectNoSuggestion(live)
        #expect(await suggestionCalls(runner).count == 1)
    }
}

@Test func aRestoredConversationEndingInAQuestionSuggestsNothing() async {
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
    let chat = ChatModel(store: scratchSessions(),
                         restoring: Session(title: "restored", workingDirectory: root,
                                            segments: [segment]),
                         cache: scratchCache,
                         registry: HarnessRegistry(harnesses: [harness]))
    chat.runner = runner

    #expect(chat.suggestedReply == nil)
    #expect(await runner.calls.isEmpty)
}

nonisolated enum Overruling: CaseIterable {
    case userReplies, userDismisses
}

@Test(arguments: Overruling.allCases)
func aSuggestionArrivingAfterItWasOverruledIsDropped(_ overruling: Overruling) async throws {
    try await withSuggestingChat { live, runner in
        await runner.answer(with: suggestion)
        await runner.hold()
        await finishTurn(live)
        await waitForSuggestionCall(runner)

        switch overruling {
        case .userReplies:
            await live.chat.send(text: "não, sem rotação")
            await live.session.emit(endOfTurn())
            await settle { !live.chat.isBusy }
        case .userDismisses:
            live.chat.dismissSuggestion()
        }
        await runner.release()

        await expectNoSuggestion(live)
    }
}

nonisolated enum UnusableOutput: CaseIterable {
    case failure, noneMarker
}

@Test(arguments: UnusableOutput.allCases)
func anUnusableQuickPromptLeavesNoSuggestionAndNoNotice(_ output: UnusableOutput) async throws {
    try await withSuggestingChat { live, runner in
        switch output {
        case .failure: await runner.fail(HarnessFailure(reason: "claude missing"))
        case .noneMarker: await runner.answer(with: ReplySuggestion.noQuestion)
        }
        await finishTurn(live)
        await waitForSuggestionCall(runner)

        await expectNoSuggestion(live)
        #expect(!live.chat.lines.contains { $0.role == .notice })
    }
}

@Test func acceptingSendsTheSuggestionAsTheUsersReply() async throws {
    try await withSuggestingChat { live, runner in
        await suggested(live, runner)

        await live.chat.acceptSuggestion()

        #expect(await live.session.sent.map(\.text).last == suggestion)
        #expect(live.chat.lines.last { $0.role == .user }?.text == suggestion)
        #expect(live.chat.suggestedReply == nil)
    }
}

@Test func acceptingTwiceSendsOnce() async throws {
    try await withSuggestingChat { live, runner in
        await suggested(live, runner)

        let first = Task { await live.chat.acceptSuggestion() }
        let second = Task { await live.chat.acceptSuggestion() }
        await first.value
        await second.value

        #expect(await live.session.sent.filter { $0.text == suggestion }.count == 1)
    }
}

@Test func dismissingClearsWithoutSending() async throws {
    try await withSuggestingChat { live, runner in
        await suggested(live, runner)
        let sentBefore = await live.session.sent.count

        live.chat.dismissSuggestion()

        #expect(live.chat.suggestedReply == nil)
        #expect(live.chat.visibleSuggestion == nil)
        #expect(await live.session.sent.count == sentBefore)
    }
}

@Test func typingHidesTheSuggestionAndClearingBringsItBack() async throws {
    try await withSuggestingChat { live, runner in
        await suggested(live, runner)

        live.chat.prompt = "n"
        #expect(live.chat.visibleSuggestion == nil)
        #expect(live.chat.suggestedReply == suggestion)

        live.chat.prompt = ""
        #expect(live.chat.visibleSuggestion == suggestion)
    }
}

@Test func aPendingAttachmentHidesTheSuggestion() async throws {
    try await withSuggestingChat { live, runner in
        await suggested(live, runner)

        live.chat.attach(imageData: Data([0x89, 0x50]))

        #expect(live.chat.visibleSuggestion == nil)
    }
}

@Test func aNewTurnStartingClearsTheSuggestion() async throws {
    try await withSuggestingChat { live, runner in
        await suggested(live, runner)

        await live.session.emit(.event(.turnStarted))

        await settle { live.chat.suggestedReply == nil }
    }
}

@Test func stoppingClearsTheSuggestion() async throws {
    try await withSuggestingChat { live, runner in
        await suggested(live, runner)

        await live.chat.stop()

        #expect(live.chat.suggestedReply == nil)
    }
}
