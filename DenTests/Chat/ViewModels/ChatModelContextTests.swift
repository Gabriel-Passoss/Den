import Testing
import Foundation
import HarnessCore
@testable import Den

private let reported = ContextUsage(
    usedTokens: 27_352, windowTokens: 200_000,
    slices: [ContextSlice(category: .messages, tokens: 27_352),
             ContextSlice(category: .freeSpace, tokens: 172_648)])

private func assistant(_ text: String) -> SessionUpdate {
    .entry(TranscriptEntry(timestamp: Date(), kind: .assistantText(text), raw: .null))
}

private let endOfTurn = SessionUpdate.entry(TranscriptEntry(
    timestamp: Date(),
    kind: .turnResult(TurnResult(usage: .zero, stopReason: "end_turn", isError: false)),
    raw: .null))

@Test func aWindowReportedWithTheUsageFillsTheRing() async throws {
    try await withLiveChat { live in
        await live.chat.start()
        await live.session.emit(.event(.contextUsage(tokens: 50_000, window: 200_000)))

        await settle { live.chat.contextFraction != nil }
        #expect(live.chat.contextFraction == 0.25)
    }
}

@Test func withoutAWindowTheRingHasNothingToFill() async throws {
    try await withLiveChat { live in
        await live.chat.start()
        await live.session.emit(.event(.contextUsage(tokens: 4_200)))

        await settle { live.chat.contextTokens == 4_200 }
        #expect(live.chat.contextFraction == nil)
    }
}

@Test func aHarnessThatReportsItsUsageIsBelieved() async throws {
    try await withLiveChat { live in
        await live.session.offer(usage: reported)
        await live.chat.start()
        await live.chat.refreshContextUsage()

        #expect(live.chat.contextUsage == reported)
        #expect(live.chat.contextTokens == 27_352)
        #expect(live.chat.contextWindow == 200_000)
    }
}

@Test func aHarnessThatCannotReportGetsAnEstimateFromTheTranscript() async throws {
    try await withLiveChat { live in
        await live.chat.start()
        await live.session.emit(assistant(String(repeating: "b", count: 4_000)))
        await live.session.emit(.event(.contextUsage(tokens: 10_000, window: 200_000)))
        await settle { live.chat.contextWindow == 200_000 }

        await live.chat.refreshContextUsage()

        let usage = try #require(live.chat.contextUsage)
        #expect(usage.isEstimate)
        #expect(usage.usedTokens == 10_000)
        #expect(usage.slices.first { $0.category == .messages }?.tokens == 1_000)
    }
}

@Test func withoutAnyNumbersThereIsNothingToShow() async throws {
    try await withLiveChat { live in
        await live.chat.start()
        await live.chat.refreshContextUsage()

        #expect(live.chat.contextUsage == nil)
    }
}

@Test func theUsageIsAskedForAsSoonAsTheSessionIsUp() async throws {
    try await withLiveChat { live in
        await live.session.offer(usage: reported)
        await live.chat.start()

        await settle { live.chat.contextUsage == reported }
        #expect(live.chat.contextWindow == 200_000)
    }
}

@Test func theUsageIsAskedForAgainWhenATurnEnds() async throws {
    try await withLiveChat { live in
        await live.chat.start()
        await settle { live.chat.isLive }
        let before = await live.session.usageRequests

        await live.session.emit(endOfTurn)

        var after = before
        let deadline = ContinuousClock.now + .seconds(1)
        while after == before, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
            after = await live.session.usageRequests
        }
        #expect(after > before)
    }
}

@Test func switchingHarnessForgetsTheOldContext() async throws {
    let other = FakeHarness(id: "other", displayName: "Other")
    try await withLiveChat(alongside: [other]) { live in
        await live.session.offer(usage: reported)
        await live.chat.start()
        await settle { live.chat.contextUsage != nil }

        await live.chat.switchHarness(to: other.id)

        #expect(live.chat.contextTokens == 0)
        #expect(live.chat.contextWindow == nil)
        #expect(live.chat.contextUsage == nil)
    }
}

@Test func theEstimateOnlyWeighsTheCurrentHarnessesTranscript() async throws {
    let other = FakeHarness(id: "other", displayName: "Other")
    try await withLiveChat(alongside: [other]) { live in
        await live.chat.start()
        await live.session.emit(assistant(String(repeating: "x", count: 40_000)))
        await settle { live.chat.lines.contains { $0.role == .assistant } }

        await live.chat.switchHarness(to: other.id)
        await other.session.emit(assistant(String(repeating: "b", count: 400)))
        await other.session.emit(.event(.contextUsage(tokens: 5_000, window: 200_000)))
        await settle { live.chat.contextWindow == 200_000 }
        await live.chat.refreshContextUsage()

        let usage = try #require(live.chat.contextUsage)
        #expect(usage.slices.first { $0.category == .messages }?.tokens == 100)
    }
}

private func restoredChat(measured: ContextUsage?, entries: [TranscriptEntry] = []) -> ChatModel {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "DenTests-" + UUID().uuidString)
    let segment = Segment(harness: HarnessID(rawValue: "test-" + UUID().uuidString),
                          harnessSessionID: "", model: "", entries: entries,
                          context: measured)
    let session = Session(title: "restored", workingDirectory: root, segments: [segment])
    return ChatModel(store: FileTranscriptStore(root: root),
                     restoring: session, cache: scratchCache)
}

@Test func aMeasuredUsageIsSavedWithTheSession() async throws {
    try await withLiveChat { live in
        await live.session.offer(usage: reported)
        await live.chat.start()
        await live.chat.refreshContextUsage()

        let saved = try await live.store.load(live.chat.sessionID)
        #expect(saved.segments.last?.context == reported)
    }
}

@Test func aReopenedSessionShowsTheUsageLastMeasured() {
    let chat = restoredChat(measured: reported)

    #expect(chat.contextUsage == reported)
    #expect(chat.contextWindow == 200_000)
    #expect(chat.contextTokens == 27_352)
    #expect(chat.contextFraction != nil)
}

@Test func aReopenedSessionKeepsItsMeasurementUntilTheHarnessIsBack() async {
    let chat = restoredChat(measured: reported)

    await chat.refreshContextUsage()

    #expect(chat.contextUsage == reported)
    #expect(chat.contextUsage?.isEstimate == false)
}

@Test func aSessionNeverMeasuredReopensWithoutUsage() {
    let chat = restoredChat(measured: nil)

    #expect(chat.contextUsage == nil)
    #expect(chat.contextWindow == nil)
}
