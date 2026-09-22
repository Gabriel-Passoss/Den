import Testing
import Foundation
import HarnessCore
@testable import OpenCodeHarness

private let clock = Date(timeIntervalSince1970: 1_000_000)

private func mapper() -> OpenCodeEventMapper { OpenCodeEventMapper(now: { clock }) }

private func kindName(_ kind: TranscriptEntry.Kind) -> String {
    switch kind {
    case .userMessage: "userMessage"
    case .assistantText: "assistantText"
    case .assistantThinking: "assistantThinking"
    case .toolCall: "toolCall"
    case .toolResult: "toolResult"
    case .permissionRequest: "permissionRequest"
    case .permissionDecision: "permissionDecision"
    case .systemNotice: "systemNotice"
    case .turnResult: "turnResult"
    case .contextCompacted: "contextCompacted"
    case .unrecognized(let discriminator, _): "unrecognized(\(discriminator))"
    }
}

private func update(_ text: String) -> JSONValue {
    try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

/// Roda a fixture inteira: cada `session/update` pelo mapper, e o resultado
/// do `session/prompt` pelo `turnResult`.
private func runFixture(_ name: String) throws -> MappedOutput {
    let url = try #require(Bundle.module.url(
        forResource: "Fixtures/\(name)", withExtension: "ndjson"))
    var subject = mapper()
    var all = MappedOutput.empty

    for line in try String(contentsOf: url, encoding: .utf8)
        .split(separator: "\n") where !line.isEmpty {
        let frame = ACPFrame.classify(Data(line.utf8))
        let out: MappedOutput
        switch frame {
        case .notification(let method, let params) where method == "session/update":
            out = subject.map(update: params["update"] ?? .null)
        case .response(_, .success(let result)):
            out = subject.turnResult(result)
        default:
            continue
        }
        all.events += out.events
        all.entries += out.entries
    }
    return all
}

// MARK: - A espinha da fixture real

@Test func theRecordedTurnProducesItsSpine() throws {
    let output = try runFixture("turn-with-permission")

    #expect(output.entries.map { kindName($0.kind) } == [
        "assistantText", "toolCall", "toolResult", "assistantText", "turnResult",
    ])
}

@Test func theChunksAccumulateIntoOneAssistantEntry() throws {
    let output = try runFixture("turn-with-permission")

    guard case .assistantText(let text) = output.entries[0].kind else {
        Issue.record("a primeira entrada devia ser texto do assistente"); return
    }

    #expect(text == "I'll run the command.")
}

@Test func theDeltaStreamNeverReachesTheTranscript() throws {
    let output = try runFixture("turn-with-permission")

    let deltas = output.events.filter { event in
        if case .textDelta = event { true } else { false }
    }
    #expect(deltas.count == 4)
    #expect(output.events.count == deltas.count + 1,
            "além dos deltas, só o contexto reportado no fim do turno")
}

@Test func theToolCallKeepsItsNameAndTheResultItsOutput() throws {
    let output = try runFixture("turn-with-permission")

    guard case .toolCall(let call) = output.entries[1].kind,
          case .toolResult(let result) = output.entries[2].kind else {
        Issue.record("esperava chamada e resultado de ferramenta"); return
    }

    #expect(call.rawName == "bash")
    #expect(call.canonical == .execute)
    #expect(call.input["command"]?.stringValue == "echo oi")

    #expect(result.callID == call.id)
    #expect(result.isError == false)
    #expect(result.content.stringValue == "oi\n")
}

@Test func theRepeatedInProgressUpdatesSettleIntoASingleResult() throws {
    let output = try runFixture("turn-with-permission")

    let results = output.entries.filter { if case .toolResult = $0.kind { true } else { false } }
    #expect(results.count == 1, "a ferramenta foi anunciada uma vez e concluída uma vez")

    let calls = output.entries.filter { if case .toolCall = $0.kind { true } else { false } }
    #expect(calls.count == 1)
}

@Test func theTurnResultCarriesTheRecordedUsage() throws {
    let output = try runFixture("turn-with-permission")

    guard case .turnResult(let result) = output.entries.last?.kind else {
        Issue.record("o turno devia fechar com turnResult"); return
    }
    #expect(result.stopReason == "end_turn")
    #expect(result.isError == false)
    #expect(result.usage.inputTokens == 34)
    #expect(result.usage.outputTokens == 8)
    #expect(result.usage.cacheReadTokens == 19784)
}

@Test func theCommandListFeedsTheMenuAndStaysOutOfTheTranscript() throws {
    let output = try runFixture("available-commands")

    #expect(output.entries.isEmpty, "catálogo não é conversa")
    guard case .catalogUpdated(let catalog) = try #require(output.events.first) else {
        Issue.record("esperava .catalogUpdated"); return
    }
    #expect(catalog.skills.count == 45)
    #expect(catalog.skills == catalog.skills.sorted())
    #expect(catalog.servers.isEmpty, "o ACP não lista servidores MCP")
    #expect(catalog.supportsCompact, "o /compact é atendido sem ser anunciado")
}

@Test func theContextOfTheTurnComesFromTheUsageUpdate() throws {
    var subject = mapper()
    let out = subject.map(update: update(
        #"{"sessionUpdate":"usage_update","used":19818,"size":200000,"cost":{"amount":0.12}}"#))

    #expect(out.events == [.contextUsage(tokens: 19818)])
    #expect(out.entries.isEmpty)
}

@Test func theBoundaryCarriesTheContextWhenAFreshUsageArrives() throws {
    var subject = mapper()
    _ = subject.map(update: update(
        #"{"sessionUpdate":"usage_update","used":87000,"size":200000}"#))
    subject.beginCompaction()
    _ = subject.map(update: update(
        #"{"sessionUpdate":"usage_update","used":7000,"size":200000}"#))
    _ = subject.map(update: update(summaryChunk))

    let closed = subject.turnResult(update(#"{"stopReason":"end_turn"}"#))
    guard case .contextCompacted(let compaction) = try #require(closed.entries.first).kind else {
        Issue.record("esperava contextCompacted"); return
    }
    #expect(compaction.tokensBefore == 87_000)
    #expect(compaction.tokensAfter == 7_000)
}

// MARK: - Variantes que a fixture não cobre

@Test func aThoughtChunkBecomesThinkingNotText() {
    var subject = mapper()
    _ = subject.map(update: update(
        #"{"sessionUpdate":"agent_thought_chunk","messageId":"prt_1","content":{"type":"text","text":"Let me run"}}"#))
    let flushed = subject.flush()

    guard case .assistantThinking(let text) = flushed.entries.first?.kind else {
        Issue.record("pensamento virou outra coisa"); return
    }
    #expect(text == "Let me run")
}

@Test func switchingFromThoughtToTextClosesTheThought() {
    var subject = mapper()
    _ = subject.map(update: update(
        #"{"sessionUpdate":"agent_thought_chunk","messageId":"prt_1","content":{"type":"text","text":"pensando"}}"#))
    let out = subject.map(update: update(
        #"{"sessionUpdate":"agent_message_chunk","messageId":"msg_1","content":{"type":"text","text":"falando"}}"#))

    #expect(out.entries.map { kindName($0.kind) } == ["assistantThinking"])
}

@Test func aFailedToolIsMarkedAsAnError() {
    var subject = mapper()
    let out = subject.map(update: update(
        #"{"sessionUpdate":"tool_call_update","toolCallId":"c1","kind":"execute","status":"failed","rawOutput":{"output":"não deu"}}"#))

    guard case .toolResult(let result) = out.entries.last?.kind else {
        Issue.record("esperava resultado de ferramenta"); return
    }
    #expect(result.isError)
    #expect(result.content.stringValue == "não deu")
}

@Test func aResultThatOnlyHasContentBlocksStillCarriesItsText() {
    var subject = mapper()
    let out = subject.map(update: update(
        #"{"sessionUpdate":"tool_call_update","toolCallId":"c1","kind":"read","status":"completed","content":[{"type":"content","content":{"type":"text","text":"linha um"}}]}"#))

    guard case .toolResult(let result) = out.entries.last?.kind else {
        Issue.record("esperava resultado de ferramenta"); return
    }
    #expect(result.content.stringValue == "linha um")
}

@Test func anUpdateThisVersionDoesNotKnowDegradesInsteadOfVanishing() {
    var subject = mapper()
    let out = subject.map(update: update(
        #"{"sessionUpdate":"weather_update","temperature":21}"#))

    guard case .unrecognized(let discriminator, let payload) = out.entries.first?.kind else {
        Issue.record("spec §5.4: o desconhecido precisa sobreviver, não sumir"); return
    }
    #expect(discriminator == "opencode:weather_update")
    #expect(payload["temperature"]?.intValue == 21)
}

@Test func everyToolKindInTheProtocolHasACanonicalReading() {
    #expect(OpenCodeToolVocabulary.canonical(for: "read") == .read)
    #expect(OpenCodeToolVocabulary.canonical(for: "edit") == .edit)
    #expect(OpenCodeToolVocabulary.canonical(for: "execute") == .execute)
    #expect(OpenCodeToolVocabulary.canonical(for: "search") == .search)
    #expect(OpenCodeToolVocabulary.canonical(for: "fetch") == .fetch)
    #expect(OpenCodeToolVocabulary.canonical(for: "delete") == .write)
    #expect(OpenCodeToolVocabulary.canonical(for: "move") == .write)

    #expect(OpenCodeToolVocabulary.canonical(for: "think") == nil)
    #expect(OpenCodeToolVocabulary.canonical(for: "other") == nil)
}

@Test func aPendingToolIsNotAnnouncedUntilItsArgumentExists() {
    var subject = mapper()

    let announcedTooEarly = subject.map(update: update(
        #"{"sessionUpdate":"tool_call","toolCallId":"c1","title":"bash","kind":"execute","status":"pending","rawInput":{"cwd":"/tmp"}}"#))
    #expect(announcedTooEarly.entries.isEmpty,
            "no pending o CLI ainda não sabe o comando — anunciar aqui grava uma ferramenta vazia")

    let announced = subject.map(update: update(
        #"{"sessionUpdate":"tool_call_update","toolCallId":"c1","status":"in_progress","kind":"execute","title":"echo oi","rawInput":{"command":"echo oi","cwd":"/tmp"}}"#))

    guard case .toolCall(let call) = announced.entries.first?.kind else {
        Issue.record("a ferramenta devia ser anunciada quando o argumento chega"); return
    }
    #expect(call.input["command"]?.stringValue == "echo oi")
}

@Test func aTerminalFrameWithNullInputDoesNotEraseTheCommand() {
    var subject = mapper()
    _ = subject.map(update: update(
        #"{"sessionUpdate":"tool_call","toolCallId":"c1","title":"bash","kind":"execute","status":"pending","rawInput":{"cwd":"/tmp"}}"#))
    let announced = subject.map(update: update(
        #"{"sessionUpdate":"tool_call_update","toolCallId":"c1","status":"completed","rawInput":null,"rawOutput":{"output":"oi"}}"#))

    guard case .toolCall(let call) = announced.entries.first?.kind else {
        Issue.record("a ferramenta precisa ser anunciada mesmo indo direto para o fim"); return
    }

    #expect(call.input["cwd"]?.stringValue == "/tmp")
}

@Test func aToolLeftHangingIsStillAnnouncedWhenTheTurnCloses() {
    var subject = mapper()
    _ = subject.map(update: update(
        #"{"sessionUpdate":"tool_call","toolCallId":"c1","title":"bash","kind":"execute","status":"pending","rawInput":{"cwd":"/tmp"}}"#))

    let closed = subject.turnResult(update(#"{"stopReason":"cancelled"}"#))

    #expect(closed.entries.map { kindName($0.kind) } == ["toolCall", "turnResult"],
            "uma ferramenta presa em pending não pode sumir do transcript")
}

@Test func anInterruptedTurnIsNotRecordedAsAFailure() {
    var subject = mapper()
    let closed = subject.turnResult(update(#"{"stopReason":"cancelled"}"#))

    guard case .turnResult(let result) = closed.entries.last?.kind else {
        Issue.record("esperava turnResult"); return
    }

    #expect(result.stopReason == "cancelled")
    #expect(result.isError == false)
}

// MARK: - Compactação

private let summaryChunk = #"""
{"sessionUpdate":"agent_message_chunk","messageId":"m1",
 "content":{"type":"text","text":"## Objective\n- fechar o commit"}}
"""#

private let secondSummaryChunk = #"""
{"sessionUpdate":"agent_message_chunk","messageId":"m2",
 "content":{"type":"text","text":"## Next Move\n- gerar a build"}}
"""#

private let thoughtChunk = #"""
{"sessionUpdate":"agent_thought_chunk","messageId":"t1",
 "content":{"type":"text","text":"**Organizing files**"}}
"""#

@Test func theSummaryOfACompactionComesPrecededByItsBoundary() throws {
    var subject = mapper()
    subject.beginCompaction()

    _ = subject.map(update: update(summaryChunk))
    let closed = subject.turnResult(update(#"{"stopReason":"end_turn"}"#))

    #expect(closed.entries.map { kindName($0.kind) }
            == ["contextCompacted", "assistantText", "turnResult"],
            "a fronteira entra imediatamente antes do resumo")
}

@Test func theBoundaryAdmitsItDoesNotKnowTheTokens() throws {
    var subject = mapper()
    subject.beginCompaction()

    _ = subject.map(update: update(summaryChunk))
    let closed = subject.turnResult(update(#"{"stopReason":"end_turn"}"#))

    guard case .contextCompacted(let compaction) = try #require(closed.entries.first).kind else {
        Issue.record("esperava contextCompacted"); return
    }
    #expect(compaction.trigger == .manual)
    #expect(compaction.tokensBefore == 0, "o ACP não informa o contexto anterior")
    #expect(compaction.tokensAfter == 0, "nem o que sobrou")
}

@Test func theSummaryDoesNotStreamWhileCompacting() throws {
    var subject = mapper()
    subject.beginCompaction()

    #expect(subject.map(update: update(summaryChunk)).events.isEmpty,
            "quem desenha o turno é o cartão de progresso")
}

@Test func aTurnThatIsNotACompactionKeepsItsProseAndItsDeltas() throws {
    var subject = mapper()

    let open = subject.map(update: update(summaryChunk))
    let closed = subject.turnResult(update(#"{"stopReason":"end_turn"}"#))

    #expect(open.events.count == 1)
    #expect(closed.entries.map { kindName($0.kind) } == ["assistantText", "turnResult"])
}

@Test func theWholeCompactionTurnCollapsesIntoOneSummary() throws {
    var subject = mapper()
    subject.beginCompaction()

    _ = subject.map(update: update(summaryChunk))
    _ = subject.map(update: update(thoughtChunk))
    _ = subject.map(update: update(secondSummaryChunk))
    let closed = subject.turnResult(update(#"{"stopReason":"end_turn"}"#))

    #expect(closed.entries.map { kindName($0.kind) }
            == ["contextCompacted", "assistantText", "turnResult"],
            "o resumo sai em partes e vira um registro só")

    guard case .assistantText(let summary) = closed.entries[1].kind else {
        Issue.record("esperava o resumo"); return
    }
    #expect(summary.contains("fechar o commit"))
    #expect(summary.contains("gerar a build"), "a segunda parte não se perde")
    #expect(!summary.contains("Organizing"), "o raciocínio do sumarizador não é conversa")
}

@Test func theReplayOfASessionOnlyCarriesState() throws {
    let replayed = OpenCodeSession.replayable(MappedOutput(events: [
        .turnStarted,
        .textDelta(blockIndex: 0, text: "velho"),
        .thinkingDelta(blockIndex: 0, text: "velho"),
        .contextUsage(tokens: 19_818),
        .catalogUpdated(CommandCatalog(skills: ["tdd"], supportsCompact: true)),
    ]))

    #expect(replayed == [.contextUsage(tokens: 19_818),
                         .catalogUpdated(CommandCatalog(skills: ["tdd"],
                                                        supportsCompact: true))],
            "o histórico reproduzido não volta como conversa nova")
}

@Test func aCompactionThatEndsWithoutProseLeavesNoBoundary() throws {
    var subject = mapper()
    subject.beginCompaction()

    let closed = subject.turnResult(update(#"{"stopReason":"cancelled"}"#))
    #expect(closed.entries.map { kindName($0.kind) } == ["turnResult"])

    _ = subject.map(update: update(summaryChunk))
    let next = subject.turnResult(update(#"{"stopReason":"end_turn"}"#))
    #expect(next.entries.map { kindName($0.kind) } == ["assistantText", "turnResult"],
            "a compactação cancelada não contamina o turno seguinte")
}
