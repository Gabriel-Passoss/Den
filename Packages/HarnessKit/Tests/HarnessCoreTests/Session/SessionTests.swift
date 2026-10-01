import Testing
import Foundation
@testable import HarnessCore

private let harnessA = HarnessID(rawValue: "harness-a")
private let harnessB = HarnessID(rawValue: "harness-b")

private let when = Date(timeIntervalSince1970: 1_700_000_000)

private func entry(_ text: String) -> TranscriptEntry {
    TranscriptEntry(timestamp: when, kind: .assistantText(text), raw: .null)
}

private func segment(
    _ harness: HarnessID,
    entries: [TranscriptEntry] = [],
    usage: UsageTotals = .zero,
    seededBy: Handoff? = nil
) -> Segment {
    Segment(id: UUID(), harness: harness, harnessSessionID: UUID().uuidString,
            model: "algum-modelo", entries: entries, usage: usage, seededBy: seededBy)
}

@Test func oneSessionSpansSeveralHarnesses() {

    let session = Session(
        id: UUID(), title: "refatorar o webhook",
        workingDirectory: URL(fileURLWithPath: "/tmp/repo"),
        segments: [
            segment(harnessA, entries: [entry("one"), entry("two")]),
            segment(harnessB, entries: [entry("three")],
                    seededBy: .briefing("resumo do que foi feito")),
        ])
    #expect(session.segments.count == 2)
    #expect(session.allEntries.map(\.id).count == 3)
    #expect(session.segments.map(\.harness) == [harnessA, harnessB])
}

@Test func theTranscriptIsTheConcatenationOfItsSegmentsInOrder() {
    let session = Session(
        id: UUID(), title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
        segments: [
            segment(harnessA, entries: [entry("a"), entry("b")]),
            segment(harnessA, entries: [entry("c")]),
        ])
    let texts = session.allEntries.compactMap { e -> String? in
        if case .assistantText(let t) = e.kind { return t }
        return nil
    }
    #expect(texts == ["a", "b", "c"])
}

@Test func usageAggregatesAcrossSegmentsBecauseTokensRunOutPerProvider() {
    let session = Session(
        id: UUID(), title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
        segments: [
            segment(harnessA, usage: UsageTotals(inputTokens: 100, outputTokens: 10, costUSD: 1)),
            segment(harnessB,
                    usage: UsageTotals(inputTokens: 50, outputTokens: 5, costUSD: 0.5)),
        ])
    #expect(session.totalUsage.inputTokens == 150)
    #expect(session.totalUsage.outputTokens == 15)
    #expect(session.totalUsage.costUSD == 1.5)
}

@Test func aHandoffRecordsHowTheNextSegmentWasSeeded() throws {
    let briefed = segment(harnessA, seededBy: .briefing("what has been done so far"))
    let target = UUID()
    let replayed = segment(harnessA, seededBy: .replay(throughEntry: target))
    #expect(briefed.seededBy == .briefing("what has been done so far"))
    #expect(replayed.seededBy == .replay(throughEntry: target))
    #expect(segment(harnessA).seededBy == nil)
}

@Test func aSessionSurvivesACodableRoundTrip() throws {
    let session = Session(
        id: UUID(), title: "with accents é", workingDirectory: URL(fileURLWithPath: "/tmp/a b"),
        segments: [segment(harnessA, entries: [entry("x")],
                           usage: UsageTotals(inputTokens: 3), seededBy: .briefing("b"))])
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let back = try decoder.decode(Session.self, from: try encoder.encode(session))
    #expect(back == session)
    #expect(back.workingDirectory.path == "/tmp/a b")
}

@Test func aSummaryDerivesTheMetadataFromTheSessionAndTakesTheCountFromTheCaller() {
    let session = Session(
        id: UUID(), title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
        segments: [
            segment(harnessA, entries: [entry("a"), entry("b")],
                    usage: UsageTotals(inputTokens: 7)),
            segment(harnessB, entries: [entry("c")]),
        ])
    let summary = SessionSummary(session: session, entryCount: session.allEntries.count, updatedAt: when)
    #expect(summary.id == session.id)
    #expect(summary.entryCount == 3)
    #expect(summary.harnesses == [harnessA, harnessB])
    #expect(summary.usage.inputTokens == 7)
    #expect(summary.updatedAt == when)
}

@Test func aSummaryOfAPartiallyLoadedSessionTrustsTheCallersEntryCountNotTheEmptyArrays() {

    let session = Session(
        id: UUID(), title: "partially loaded session",
        workingDirectory: URL(fileURLWithPath: "/tmp"),
        segments: [
            segment(harnessA, entries: [], usage: UsageTotals(inputTokens: 100)),
            segment(harnessB, entries: [], usage: UsageTotals(inputTokens: 50)),
        ])
    #expect(session.allEntries.isEmpty)

    let summary = SessionSummary(session: session, entryCount: 347, updatedAt: when)
    #expect(summary.usage.inputTokens == 150)
    #expect(summary.entryCount == 347)
}

private let measuredContext = ContextUsage(
    usedTokens: 27_352, windowTokens: 200_000,
    slices: [ContextSlice(category: .messages, tokens: 27_352)])

private func decodedSegment(_ json: String) throws -> Segment {
    try JSONDecoder().decode(Segment.self, from: Data(json.utf8))
}

private let savedBeforeContext = """
    {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","harness":"harness-a",
     "harnessSessionID":"abc","model":"algum-modelo","entries":[],
     "usage":{"inputTokens":0,"outputTokens":0,"cacheReadTokens":0,"cacheCreationTokens":0,"costUSD":0}}
    """

@Test func aSegmentKeepsTheContextLastMeasuredInIt() throws {
    var kept = segment(harnessA)
    kept.context = measuredContext
    let decoded = try JSONDecoder().decode(Segment.self, from: JSONEncoder().encode(kept))
    #expect(decoded == kept)
}

@Test func aSegmentWithoutAMeasurementSavesNoContext() throws {
    let data = try JSONEncoder().encode(segment(harnessA))
    #expect(!String(decoding: data, as: UTF8.self).contains("context"))
}

@Test func aSegmentSavedBeforeContextWasKeptStillLoads() throws {
    let decoded = try decodedSegment(savedBeforeContext)
    #expect(decoded.harnessSessionID == "abc")
    #expect(decoded.context == nil)
}

@Test func anUnreadableContextNeverCostsTheSegment() throws {
    let damaged = savedBeforeContext.replacingOccurrences(
        of: #""entries":[],"#, with: #""entries":[],"context":{"usedTokens":"many"},"#)
    let decoded = try decodedSegment(damaged)
    #expect(decoded.harnessSessionID == "abc")
    #expect(decoded.context == nil)
}
