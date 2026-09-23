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

// MARK: - Caso 10: um discriminador que esta versão não conhece

private func decodeEntry(_ json: String) throws -> TranscriptEntry {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(TranscriptEntry.self, from: Data(json.utf8))
}

private func decodeAsJSONValue(_ data: Data) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: data)
}

private let unknownKindJSON = """
{
  "id": "11111111-1111-1111-1111-111111111111",
  "timestamp": "2023-11-14T22:13:20Z",
  "kind": {"subagentSpawn": {"agentType": "reviewer", "id": "s1"}},
  "raw": {"type": "subagentSpawn", "agentType": "reviewer"}
}
"""

@Test func anUnknownDiscriminatorDecodesToUnrecognizedWithoutLosingTheEnvelope() throws {
    let entry = try decodeEntry(unknownKindJSON)
    #expect(entry.id == fixedID)
    #expect(entry.timestamp == fixedDate)
    #expect(entry.raw["type"] == .string("subagentSpawn"))
    guard case .unrecognized(let discriminator, let payload) = entry.kind else {
        Issue.record("esperava .unrecognized, achei \(entry.kind)"); return
    }
    #expect(discriminator == "subagentSpawn")
    #expect(payload["agentType"] == .string("reviewer"))
    #expect(payload["id"] == .string("s1"))
}

@Test func theNineKnownCasesStillDecodeToThemselvesNotToUnrecognized() throws {

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
        let decoded = try roundTrip(entry)
        if case .unrecognized = decoded.kind {
            Issue.record("caso conhecido caiu no fallback: \(kind)")
        }
        #expect(decoded.kind == kind)
    }
}

@Test func decodingAnUnknownCaseAndReencodingItIsIdempotent() throws {

    let originalData = Data(unknownKindJSON.utf8)
    let entry = try decodeEntry(unknownKindJSON)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let reencodedData = try encoder.encode(entry)

    let originalJSON = try decodeAsJSONValue(originalData)
    let reencodedJSON = try decodeAsJSONValue(reencodedData)
    #expect(reencodedJSON == originalJSON)

    #expect(reencodedJSON["kind"]?["subagentSpawn"] != nil)
    #expect(reencodedJSON["kind"]?["unrecognized"] == nil)
}

@Test func aGenuinelyMalformedEntryStillFailsLoudly() {

    let missingID = """
    {
      "timestamp": "2023-11-14T22:13:20Z",
      "kind": {"assistantText": {"_0": "oi"}},
      "raw": null
    }
    """
    #expect(throws: (any Error).self) { try decodeEntry(missingID) }

    let kindNotAnObject = """
    {
      "id": "11111111-1111-1111-1111-111111111111",
      "timestamp": "2023-11-14T22:13:20Z",
      "kind": "assistantText",
      "raw": null
    }
    """
    #expect(throws: (any Error).self) { try decodeEntry(kindNotAnObject) }
}
