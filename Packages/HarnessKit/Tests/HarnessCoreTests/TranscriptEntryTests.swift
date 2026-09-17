import Testing
import Foundation
@testable import HarnessCore

private let fixedID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

private func roundTrip(_ entry: TranscriptEntry) throws -> TranscriptEntry {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(TranscriptEntry.self, from: try encoder.encode(entry))
}

@Test func everyKindSurvivesARoundTrip() throws {
    let kinds: [TranscriptEntry.Kind] = [
        .userMessage(text: "oi", attachments: []),
        .assistantText("olá"),
        .assistantThinking("hmm"),
        .toolCall(ToolCall(id: "t1", rawName: "Bash", canonical: .execute,
                           input: .object(["command": .string("ls")]))),
        .toolResult(ToolResult(callID: "t1", isError: false, content: .string("a\nb"))),
        .permissionRequest(PermissionRequest(
            id: "r1", toolName: "Write", displayName: "Write", description: nil,
            input: .object([:]), toolUseID: "t2", suggestions: [])),
        .permissionDecision(requestID: "r1", .allow(updatedInput: nil)),
        .systemNotice(subtype: "init", text: "sessão iniciada"),
        .turnResult(TurnResult(usage: UsageTotals(inputTokens: 10, outputTokens: 20,
                                                  cacheReadTokens: 0, cacheCreationTokens: 0,
                                                  costUSD: 0.01),
                               stopReason: "end_turn", isError: false)),
    ]
    for kind in kinds {
        let entry = TranscriptEntry(id: fixedID, timestamp: fixedDate, kind: kind, raw: .null)
        #expect(try roundTrip(entry) == entry, "caso não sobreviveu: \(kind)")
    }
}

@Test func theRawPayloadIsPreservedWholeNotSummarized() throws {
    // Spec §4.1: o canônico serve ao handoff e à UI; o raw garante que nada é
    // perdido. Um raw resumido quebraria o replay.
    let raw = JSONValue.object([
        "type": .string("assistant"),
        "message": .object(["role": .string("assistant"), "extra": .int(7)]),
    ])
    let entry = TranscriptEntry(id: fixedID, timestamp: fixedDate,
                                kind: .assistantText("olá"), raw: raw)
    #expect(try roundTrip(entry).raw == raw)
    #expect(try roundTrip(entry).raw["message"]?["extra"] == .int(7))
}

@Test func twoEntriesWithDifferentIDsAreNotEqual() {
    let a = TranscriptEntry(id: UUID(), timestamp: fixedDate, kind: .assistantText("x"), raw: .null)
    let b = TranscriptEntry(id: UUID(), timestamp: fixedDate, kind: .assistantText("x"), raw: .null)
    #expect(a != b)
}

@Test func anAttachmentCarriesItsPathAndKind() throws {
    let entry = TranscriptEntry(
        id: fixedID, timestamp: fixedDate,
        kind: .userMessage(text: "veja", attachments: [
            Attachment(kind: "image", path: "/tmp/a.png", raw: .null),
        ]),
        raw: .null)
    guard case .userMessage(_, let attachments) = try roundTrip(entry).kind else {
        Issue.record("esperava userMessage"); return
    }
    #expect(attachments.first?.path == "/tmp/a.png")
    #expect(attachments.first?.kind == "image")
}

@Test func usageTotalsAdd() {
    let a = UsageTotals(inputTokens: 1, outputTokens: 2, cacheReadTokens: 3,
                        cacheCreationTokens: 4, costUSD: 0.5)
    let b = UsageTotals(inputTokens: 10, outputTokens: 20, cacheReadTokens: 30,
                        cacheCreationTokens: 40, costUSD: 1.5)
    let sum = a + b
    #expect(sum.inputTokens == 11)
    #expect(sum.outputTokens == 22)
    #expect(sum.cacheReadTokens == 33)
    #expect(sum.cacheCreationTokens == 44)
    #expect(sum.costUSD == 2.0)
    #expect(UsageTotals.zero + a == a)
}
