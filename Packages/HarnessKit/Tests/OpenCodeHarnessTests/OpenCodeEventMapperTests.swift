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

    #expect(output.events.count == 4)
    for event in output.events {
        guard case .textDelta = event else {
            Issue.record("um delta virou outra coisa: \(event)"); return
        }
    }
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

@Test func theCommandListIsNoiseAndStaysOutOfTheTranscript() throws {
    let output = try runFixture("available-commands")

    #expect(output.entries.isEmpty)
    #expect(output.events.isEmpty)
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
