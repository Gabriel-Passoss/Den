import Testing
import Foundation
@testable import HarnessCore
import HarnessTestSupport

private let encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return e
}()

private let decoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
}()

private func json(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

private struct Golden {
    let discriminator: String
    let kind: TranscriptEntry.Kind
    let wire: String
}

private let golden: [Golden] = [
    Golden(
        discriminator: "userMessage",
        kind: .userMessage(text: "olá, ç", attachments: [
            Attachment(kind: "image", path: "/tmp/a.png", raw: .object(["w": .int(2)])),
        ]),
        wire: #"{"userMessage":{"attachments":[{"kind":"image","path":"/tmp/a.png","raw":{"w":2}}],"text":"olá, ç"}}"#
    ),
    Golden(
        discriminator: "assistantText",
        kind: .assistantText("hi"),
        wire: #"{"assistantText":{"_0":"hi"}}"#
    ),
    Golden(
        discriminator: "assistantThinking",
        kind: .assistantThinking("hmm"),
        wire: #"{"assistantThinking":{"_0":"hmm"}}"#
    ),
    Golden(
        discriminator: "toolCall",
        kind: .toolCall(ToolCall(id: "t1", rawName: "Bash", canonical: .execute,
                                 input: .object(["command": .string("ls")]))),
        wire: #"{"toolCall":{"_0":{"canonical":"execute","id":"t1","input":{"command":"ls"},"rawName":"Bash"}}}"#
    ),
    Golden(
        discriminator: "toolResult",
        kind: .toolResult(ToolResult(callID: "t1", isError: false, content: .string("a\nb"))),
        wire: #"{"toolResult":{"_0":{"callID":"t1","content":"a\nb","isError":false}}}"#
    ),
    Golden(
        discriminator: "permissionRequest",
        kind: .permissionRequest(PermissionRequest(
            id: "r1", toolName: "Write", displayName: "Escrever", description: "d",
            input: .object(["path": .string("/tmp/x")]), toolUseID: "t2",
            suggestions: [PermissionSuggestion(type: "setMode", mode: "acceptEdits",
                                               destination: "session", behavior: "allow",
                                               raw: .object(["k": .bool(true)]))],
            options: [PermissionOption(id: "allow", kind: .allowOnce, label: "Permitir")])),
        wire: #"{"permissionRequest":{"_0":{"description":"d","displayName":"Escrever","id":"r1","input":{"path":"/tmp/x"},"options":[{"id":"allow","kind":"allowOnce","label":"Permitir"}],"suggestions":[{"behavior":"allow","destination":"session","mode":"acceptEdits","raw":{"k":true},"type":"setMode"}],"toolName":"Write","toolUseID":"t2"}}}"#
    ),

    Golden(
        discriminator: "permissionDecision",
        kind: .permissionDecision(requestID: "r1", .allow(updatedInput: .object(["p": .string("y")]))),
        wire: #"{"permissionDecision":{"_1":{"allow":{"updatedInput":{"p":"y"}}},"requestID":"r1"}}"#
    ),
    Golden(
        discriminator: "permissionDecision",
        kind: .permissionDecision(requestID: "r2", .deny(message: "no", interrupt: true)),
        wire: #"{"permissionDecision":{"_1":{"deny":{"interrupt":true,"message":"no"}},"requestID":"r2"}}"#
    ),
    Golden(
        discriminator: "systemNotice",
        kind: .systemNotice(subtype: "init", text: "session started"),
        wire: #"{"systemNotice":{"subtype":"init","text":"session started"}}"#
    ),
    Golden(
        discriminator: "turnResult",
        kind: .turnResult(TurnResult(
            usage: UsageTotals(inputTokens: 10, outputTokens: 20, cacheReadTokens: 1,
                               cacheCreationTokens: 2, costUSD: 0.01),
            stopReason: "end_turn", isError: false)),
        wire: #"{"turnResult":{"_0":{"isError":false,"stopReason":"end_turn","usage":{"cacheCreationTokens":2,"cacheReadTokens":1,"costUSD":0.01,"inputTokens":10,"outputTokens":20}}}}"#
    ),
    Golden(
        discriminator: "contextCompacted",
        kind: .contextCompacted(ContextCompaction(
            trigger: .manual, tokensBefore: 875_602, tokensAfter: 14_144, duration: 132.5)),
        wire: #"{"contextCompacted":{"_0":{"duration":132.5,"tokensAfter":14144,"tokensBefore":875602,"trigger":"manual"}}}"#
    ),
]

@Test func theKnownKindsDecodeFromTheirGoldenJSON() throws {
    for item in golden {
        let decoded = try decoder.decode(TranscriptEntry.Kind.self, from: Data(item.wire.utf8))
        #expect(decoded == item.kind, "o decoder mudou de forma para \(item.discriminator)")
        if case .unrecognized = decoded {
            Issue.record("\(item.discriminator) caiu no fallback — o nome de caso mudou")
        }
    }
}

@Test func theKnownKindsEncodeToTheirGoldenJSON() throws {
    for item in golden {
        let written = try json(String(decoding: try encoder.encode(item.kind), as: UTF8.self))
        #expect(written == (try json(item.wire)),
                "the encoder changed shape for \(item.discriminator) — every transcript on disk becomes an orphan")
    }
}

@Test func theGoldenFixturesCoverEveryDiscriminatorThisVersionKnows() {

    #expect(Set(golden.map(\.discriminator)) == TranscriptEntry.Kind.knownDiscriminators)
}

@Test func theEnvelopeOfATranscriptEntryIsFixedToo() throws {

    let wire = #"""
    {"id":"11111111-1111-1111-1111-111111111111","kind":{"assistantText":{"_0":"hi"}},"raw":{"a":1},"timestamp":"2023-11-14T22:13:20Z"}
    """#
    let expected = TranscriptEntry(
        id: try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111")),
        timestamp: Date(timeIntervalSince1970: 1_700_000_000),
        kind: .assistantText("hi"), raw: .object(["a": .int(1)]))

    #expect(try decoder.decode(TranscriptEntry.self, from: Data(wire.utf8)) == expected)
    #expect(try json(String(decoding: try encoder.encode(expected), as: UTF8.self))
            == (try json(wire)))
}

// MARK: - Handoff: the provenance this plan exists to record

private let goldenHandoffs: [(String, Handoff, String)] = [
    ("briefing", .briefing("resumo"), #"{"briefing":{"_0":"resumo"}}"#),
    ("replay", .replay(throughEntry: fixedUUID("22222222-2222-2222-2222-222222222222")),
     #"{"replay":{"throughEntry":"22222222-2222-2222-2222-222222222222"}}"#),
]

@Test func bothHandoffStrategiesRoundTripThroughTheirGoldenJSON() throws {
    for (name, handoff, wire) in goldenHandoffs {
        #expect(try decoder.decode(Handoff.self, from: Data(wire.utf8)) == handoff,
                "o decoder mudou de forma para \(name)")
        #expect(try json(String(decoding: try encoder.encode(handoff), as: UTF8.self))
                == (try json(wire)),
                "o encoder mudou de forma para \(name)")
    }
    #expect(Set(goldenHandoffs.map(\.0)) == Handoff.knownDiscriminators)
}

@Test func aSegmentCarriesItsHandoffAllTheWayToDiskAndBack() throws {

    let wire = #"""
    {"id":"55555555-5555-5555-5555-555555555555","segments":[{"entries":[],"harness":"harness-a","harnessSessionID":"44444444-4444-4444-4444-444444444444","id":"33333333-3333-3333-3333-333333333333","model":"m","seededBy":{"replay":{"throughEntry":"22222222-2222-2222-2222-222222222222"}},"usage":{"cacheCreationTokens":0,"cacheReadTokens":0,"costUSD":0,"inputTokens":5,"outputTokens":0}}],"title":"t","workingDirectory":"file:///tmp/repo"}
    """#
    let expected = Session(
        id: try #require(UUID(uuidString: "55555555-5555-5555-5555-555555555555")),
        title: "t", workingDirectory: URL(fileURLWithPath: "/tmp/repo"),
        segments: [Segment(
            id: try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333")),
            harness: HarnessID(rawValue: "harness-a"),
            harnessSessionID: "44444444-4444-4444-4444-444444444444",
            model: "m", entries: [], usage: UsageTotals(inputTokens: 5),
            seededBy: .replay(throughEntry: try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))))])

    let decoded = try decoder.decode(Session.self, from: Data(wire.utf8))
    #expect(decoded == expected)
    #expect(decoded.segments.first?.seededBy
            == .replay(throughEntry: try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))))
    #expect(try json(String(decoding: try encoder.encode(expected), as: UTF8.self))
            == (try json(wire)))
}

// MARK: - The two open enums must not drift from themselves

@Test func anUnknownHandoffStrategyDegradesAndReencodesIdempotently() throws {
    let wire = #"{"summarizeWithModel":{"model":"m-9","tokens":800}}"#
    let decoded = try decoder.decode(Handoff.self, from: Data(wire.utf8))
    guard case .unrecognized(let discriminator, let payload) = decoded else {
        Issue.record("esperava .unrecognized, achei \(decoded)"); return
    }
    #expect(discriminator == "summarizeWithModel")
    #expect(payload["model"] == .string("m-9"))
    #expect(try json(String(decoding: try encoder.encode(decoded), as: UTF8.self))
            == (try json(wire)))
}

@Test func aHandoffThatIsNotASingleKeyedObjectStillFailsLoudly() {
    #expect(throws: (any Error).self) {
        try decoder.decode(Handoff.self, from: Data(#""briefing""#.utf8))
    }
    #expect(throws: (any Error).self) {
        try decoder.decode(Handoff.self,
                           from: Data(#"{"briefing":{"_0":"a"},"replay":{"throughEntry":"x"}}"#.utf8))
    }
}

@Test func theOpenEnumsDoNotDivergeFromTheirKnownDiscriminators() throws {
    let sources = packageRoot().appending(path: "Sources/HarnessCore")

    let subjects: [(String, String, String, Set<String>, String)] = [
        ("TranscriptEntry.swift", "public enum Kind:", "private enum Known:",
         TranscriptEntry.Kind.knownDiscriminators, "TranscriptEntry.Kind"),
        ("Session.swift", "public enum Handoff:", "private enum Known:",
         Handoff.knownDiscriminators, "Handoff"),
    ]

    let located = try #require(
        FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
    )

    for (file, opening, closing, known, name) in subjects {
        let url = try #require(located.first { $0.lastPathComponent == file },
                               "could not find \(file) under Sources/HarnessCore")
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let start = try #require(lines.firstIndex { $0.contains(opening) },
                                 "could not find \(opening) in \(file) — the source changed shape")
        let end = try #require(lines[start...].firstIndex { $0.contains(closing) },
                               "could not find \(closing) in \(file) — the source changed shape")
        let declared = lines[start..<end]
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("case ") }
            .count

        #expect(declared == known.count + 1,
                "\(name) declares \(declared) cases and knows \(known.count) discriminators — a new case never reached Known.CodingKeys")
    }
}

@Test func aPermissionRequestWrittenBeforeOptionsExistedStillDecodes() throws {

    let beforeOptions = #"{"permissionRequest":{"_0":{"id":"r1","input":{"path":"/tmp/x"},"suggestions":[],"toolName":"Write"}}}"#

    let decoded = try decoder.decode(
        TranscriptEntry.Kind.self, from: Data(beforeOptions.utf8))

    guard case .permissionRequest(let request) = decoded else {
        Issue.record("fell through to the fallback — the old transcript became an orphan")
        return
    }
    #expect(request.id == "r1")
    #expect(request.toolName == "Write")

    #expect(request.options.isEmpty)
}

@Test func anOptionKindThisVersionDoesNotKnowSurvivesAsOther() throws {

    let fromTheFuture = #"{"id":"x","kind":"allowForTheNextHour","label":"Por uma hora"}"#

    let option = try decoder.decode(PermissionOption.self, from: Data(fromTheFuture.utf8))
    #expect(option.kind == .other)
    #expect(option.label == "Por uma hora")
}
