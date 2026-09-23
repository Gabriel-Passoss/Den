import Testing
import Foundation
@testable import HarnessCore

private func entry(_ kind: TranscriptEntry.Kind) -> TranscriptEntry {
    TranscriptEntry(timestamp: Date(timeIntervalSince1970: 1_000_000),
                    kind: kind, raw: .null)
}

private let conversation: [TranscriptEntry] = [
    entry(.userMessage(text: "como faço X?", attachments: [])),
    entry(.assistantThinking("o usuário quer X, vou ler o arquivo")),
    entry(.assistantText("Vou olhar o arquivo.")),
    entry(.toolCall(ToolCall(id: "c1", rawName: "Read", canonical: .read,
                             input: .object(["file_path": .string("/tmp/a.swift")])))),
    entry(.toolResult(ToolResult(callID: "c1", isError: false, content: .string("conteúdo")))),
    entry(.assistantText("Faz assim: …")),
]

@Test func theSeedCarriesBothVoicesInOrder() throws {
    let seed = try #require(HandoffSeed.make(conversation))

    let body = seed.text
    let you = try #require(body.range(of: "**Você:** como faço X?"))
    let first = try #require(body.range(of: "**Assistente:** Vou olhar o arquivo."))
    let last = try #require(body.range(of: "**Assistente:** Faz assim: …"))

    #expect(you.lowerBound < first.lowerBound)
    #expect(first.lowerBound < last.lowerBound)
}

@Test func theSeedNamesTheToolsWithoutTheirOutput() throws {
    let seed = try #require(HandoffSeed.make(conversation))

    #expect(seed.text.contains("_(usou Read: /tmp/a.swift)_"))

    #expect(!seed.text.contains("conteúdo"))
}

@Test func theSeedLeavesTheOldModelsReasoningBehind() throws {
    let seed = try #require(HandoffSeed.make(conversation))
    #expect(!seed.text.contains("o usuário quer X"))
}

@Test func theSeedTellsTheNewModelNotToAnswerTheOldConversation() throws {
    let seed = try #require(HandoffSeed.make(conversation))
    #expect(seed.text.hasPrefix(HandoffSeed.preamble))
}

@Test func aConversationThatFitsIsRecordedAsACompleteReplay() throws {
    let seed = try #require(HandoffSeed.make(conversation))

    #expect(seed.isComplete)
    #expect(seed.handoff == .replay(throughEntry: conversation.last!.id))
}

@Test func aConversationThatOverflowsKeepsTheRecentEndAndSaysSo() throws {
    var long = conversation
    for index in 0..<200 {
        long.append(entry(.userMessage(text: "pergunta \(index) " +
                                       String(repeating: "x", count: 400), attachments: [])))
        long.append(entry(.assistantText("resposta \(index)")))
    }

    let seed = try #require(HandoffSeed.make(long, budget: 4_000))

    #expect(!seed.isComplete)
    if case .briefing = seed.handoff {} else {
        Issue.record("um estouro precisa ser registrado como briefing, não como replay")
    }
    #expect(seed.text.contains(HandoffSeed.omissionMarker))

    #expect(seed.text.contains("resposta 199"))
    #expect(!seed.text.contains("como faço X?"))

    #expect(seed.text.count <= 4_000)
}

@Test func anEmptyConversationHasNothingToSeed() {
    #expect(HandoffSeed.make([]) == nil)

    #expect(HandoffSeed.make([entry(.systemNotice(subtype: "init", text: "oi"))]) == nil)
}

@Test func aBudgetTooSmallForEvenOneTurnSeedsNothing() {
    #expect(HandoffSeed.make(conversation, budget: 10) == nil)
}

@Test func aLongToolArgumentIsTrimmedInsteadOfDominating() throws {
    let huge = entry(.toolCall(ToolCall(
        id: "c", rawName: "Bash", canonical: .execute,
        input: .object(["command": .string(String(repeating: "a", count: 500))]))))
    let seed = try #require(HandoffSeed.make([
        entry(.userMessage(text: "roda", attachments: [])), huge,
    ]))
    #expect(seed.text.contains("…"))
    #expect(seed.text.count < 400)
}

// MARK: - A troca atravessando o disco

private let harnessA = HarnessID(rawValue: "harness-a")
private let harnessB = HarnessID(rawValue: "harness-b")

@Test func aSessionThatChangedHarnessSurvivesTheStore() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "handoff-\(UUID().uuidString)")
    let store = FileTranscriptStore(root: root)
    defer { try? FileManager.default.removeItem(at: root) }

    let first = Segment(harness: harnessA,
                        harnessSessionID: UUID().uuidString, model: "m1")

    let second = Segment(harness: harnessB,
                         harnessSessionID: "ses_f36f01b7dffeoyVh8oyerb5GJG",
                         model: "m2",
                         seededBy: .replay(throughEntry: conversation[0].id))

    var session = Session(id: UUID(), title: "trocou",
                          workingDirectory: URL(fileURLWithPath: "/tmp/repo"),
                          segments: [first])
    try await store.saveMetadata(session)
    try await store.append(conversation[0], to: first.id, in: session.id)

    session.segments.append(second)
    try await store.saveMetadata(session)
    try await store.append(conversation[5], to: second.id, in: session.id)

    let loaded = try await store.load(session.id)

    #expect(loaded.segments.map(\.harness) == [harnessA, harnessB])
    #expect(loaded.segments[1].harnessSessionID == "ses_f36f01b7dffeoyVh8oyerb5GJG")
    #expect(loaded.segments[1].seededBy == .replay(throughEntry: conversation[0].id))

    #expect(loaded.allEntries.count == 2)

    let listed = try await store.list()
    #expect(listed.sessions.first?.harnesses == [harnessA, harnessB])
}

@Test func appendingToASegmentTheMetadataDoesNotKnowIsRefused() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "handoff-\(UUID().uuidString)")
    let store = FileTranscriptStore(root: root)
    defer { try? FileManager.default.removeItem(at: root) }

    let first = Segment(harness: harnessA, harnessSessionID: "a", model: "m")
    let session = Session(id: UUID(), title: "t",
                          workingDirectory: URL(fileURLWithPath: "/tmp"),
                          segments: [first])
    try await store.saveMetadata(session)

    let orphan = Segment(harness: harnessB, harnessSessionID: "b", model: "m")
    await #expect(throws: TranscriptStoreError.segmentNotFound(orphan.id)) {
        try await store.append(conversation[0], to: orphan.id, in: session.id)
    }
}

// MARK: - A semente colada ao primeiro pedido

@Test func theSeedTravelsAttachedToTheRequest() throws {
    let seed = HandoffSeed.make([entry(.userMessage(text: "oi", attachments: []))])

    let message = HandoffSeed.message(seed: try #require(seed).text, request: "continue daqui")

    #expect(message.hasPrefix(HandoffSeed.preamble))
    #expect(message.contains("**Você:** oi"))
    #expect(message.hasSuffix("continue daqui"))

    #expect(message.contains(HandoffSeed.requestHeading))
}

@Test func aTurnWithOnlyAnAttachmentStillCarriesARequest() throws {
    let seed = try #require(HandoffSeed.make([entry(.userMessage(text: "oi", attachments: []))]))

    let message = HandoffSeed.message(seed: seed.text, request: "   \n ")

    #expect(message.hasSuffix(HandoffSeed.emptyRequest))
}

// MARK: - Agrupamento das opções

@Test func aFlatListIsOneUntitledGroup() {
    let knob = HarnessKnob(id: "model", category: .model, name: "Modelo", options: [
        .init(value: "a", label: "A"), .init(value: "b", label: "B"),
    ])

    #expect(knob.groupedOptions.count == 1)
    #expect(knob.groupedOptions[0].group == nil)
    #expect(knob.groupedOptions[0].options.count == 2)
}

@Test func anEmptyKnobHasNoGroups() {
    #expect(HarnessKnob(id: "x", category: .effort, name: "X").groupedOptions.isEmpty)
}
