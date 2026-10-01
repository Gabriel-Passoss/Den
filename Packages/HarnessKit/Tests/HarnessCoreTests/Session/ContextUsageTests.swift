import Testing
import Foundation
import HarnessCore

private let clock = Date(timeIntervalSince1970: 0)

private func entry(_ kind: TranscriptEntry.Kind) -> TranscriptEntry {
    TranscriptEntry(timestamp: clock, kind: kind, raw: .null)
}

private func slice(_ category: ContextCategory, in usage: ContextUsage) -> ContextSlice? {
    usage.slices.first { $0.category == category }
}

@Test func theFractionIsTheShareOfTheWindowInUse() {
    let usage = ContextUsage(usedTokens: 50_000, windowTokens: 200_000, slices: [])
    #expect(usage.fraction == 0.25)
}

@Test func theFractionNeverPassesAFullWindow() {
    let usage = ContextUsage(usedTokens: 250_000, windowTokens: 200_000, slices: [])
    #expect(usage.fraction == 1)
}

@Test func anUnknownWindowReadsAsEmpty() {
    let usage = ContextUsage(usedTokens: 50_000, windowTokens: 0, slices: [])
    #expect(usage.fraction == 0)
}

@Test func theEstimateSplitsMessagesFromToolActivity() {
    let entries = [
        entry(.userMessage(text: String(repeating: "a", count: 400), attachments: [])),
        entry(.assistantText(String(repeating: "b", count: 400))),
        entry(.toolResult(ToolResult(callID: "1", isError: false,
                                     content: .string(String(repeating: "c", count: 2_000))))),
    ]
    let usage = ContextUsage.estimate(from: entries, used: 10_000, window: 200_000)

    #expect(usage.isEstimate)
    #expect(slice(.messages, in: usage)?.tokens == 200)
    #expect(slice(.toolActivity, in: usage)?.tokens == 500)
}

@Test func whatTheTranscriptDoesNotExplainIsTheSystemsShare() {
    let entries = [entry(.assistantText(String(repeating: "b", count: 4_000)))]
    let usage = ContextUsage.estimate(from: entries, used: 10_000, window: 200_000)

    #expect(slice(.systemAndTools, in: usage)?.tokens == 9_000)
}

@Test func theFreeSpaceIsTheRestOfTheWindow() {
    let usage = ContextUsage.estimate(from: [], used: 10_000, window: 200_000)

    #expect(slice(.freeSpace, in: usage)?.tokens == 190_000)
    #expect(usage.usedTokens == 10_000)
    #expect(usage.windowTokens == 200_000)
}

@Test func aTranscriptLargerThanTheContextShrinksToFitIt() {
    let entries = [
        entry(.assistantText(String(repeating: "b", count: 4_000))),
        entry(.toolResult(ToolResult(callID: "1", isError: false,
                                     content: .string(String(repeating: "c", count: 12_000))))),
    ]
    let usage = ContextUsage.estimate(from: entries, used: 2_000, window: 200_000)

    #expect(slice(.messages, in: usage)?.tokens == 500)
    #expect(slice(.toolActivity, in: usage)?.tokens == 1_500)
    #expect(slice(.systemAndTools, in: usage) == nil)
}

@Test func onlyWhatFollowsTheLastCompactionCounts() {
    let entries = [
        entry(.assistantText(String(repeating: "x", count: 40_000))),
        entry(.contextCompacted(ContextCompaction(trigger: .manual, tokensBefore: 90_000,
                                                  tokensAfter: 3_000, duration: 1))),
        entry(.assistantText(String(repeating: "b", count: 400))),
    ]
    let usage = ContextUsage.estimate(from: entries, used: 3_000, window: 200_000)

    #expect(slice(.messages, in: usage)?.tokens == 100)
}

@Test func toolCallsCountTheirInputTowardToolActivity() {
    let call = ToolCall(id: "1", rawName: "bash", canonical: nil,
                        input: .object(["command": .string(String(repeating: "l", count: 390))]))
    let usage = ContextUsage.estimate(from: [entry(.toolCall(call))], used: 10_000, window: 200_000)

    #expect((slice(.toolActivity, in: usage)?.tokens ?? 0) >= 100)
}

private let measured = ContextUsage(
    usedTokens: 52_800, windowTokens: 1_000_000,
    slices: [ContextSlice(category: .systemTools, tokens: 17_500),
             ContextSlice(category: .mcpTools, tokens: 11_600, isDeferred: true),
             ContextSlice(category: .other("Plugins"), tokens: 300),
             ContextSlice(category: .freeSpace, tokens: 947_200)],
    details: [ContextDetail(category: .mcpTools, items: [
        ContextItem(name: "search", group: "docs", tokens: 900, isDeferred: true)])])

private func roundTrip<T: Codable>(_ value: T) throws -> T {
    try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
}

@Test func aMeasuredUsageSurvivesBeingSaved() throws {
    #expect(try roundTrip(measured) == measured)
}

@Test func aCategoryIsSavedAsItsName() throws {
    let data = try JSONEncoder().encode([ContextCategory.skills, .other("Plugins")])
    #expect(String(decoding: data, as: UTF8.self) == #"["skills","other:Plugins"]"#)
}

@Test func aCategoryThisVersionDoesNotKnowReadsAsOther() throws {
    let decoded = try JSONDecoder().decode([ContextCategory].self,
                                           from: Data(#"["messages","fromTheFuture"]"#.utf8))
    #expect(decoded == [.messages, .other("fromTheFuture")])
}
