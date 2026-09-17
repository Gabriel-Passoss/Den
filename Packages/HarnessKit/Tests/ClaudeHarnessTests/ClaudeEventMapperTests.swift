import Testing
import Foundation
@testable import HarnessCore
@testable import ClaudeHarness

/// `@testable` em `HarnessCore` para alcançar
/// `TranscriptEntry.Kind.knownDiscriminators`, que é `internal`.

/// Um instante fixo: nenhuma asserção deste arquivo depende do relógio de
/// parede.
let fixedNow = Date(timeIntervalSince1970: 1_000_000)

func makeMapper() -> ClaudeEventMapper {
    ClaudeEventMapper(now: { fixedNow })
}

func json(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

// MARK: - Deltas

@Test func aTextDeltaBecomesAnEphemeralEventAndNothingDurable() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"stream_event","event":{"type":"content_block_delta","index":0,
     "delta":{"type":"text_delta","text":"Olá"}},"session_id":"s"}
    """#))
    #expect(out.events == [.textDelta(blockIndex: 0, text: "Olá")])
    #expect(out.entries.isEmpty)
}

@Test func aThinkingDeltaReadsTheThinkingFieldNotTheTextField() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"stream_event","event":{"type":"content_block_delta","index":1,
     "delta":{"type":"thinking_delta","thinking":"hmm"}}}
    """#))
    #expect(out.events == [.thinkingDelta(blockIndex: 1, text: "hmm")])
}

@Test func anInputJSONDeltaCarriesThePartialJSONVerbatim() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"stream_event","event":{"type":"content_block_delta","index":2,
     "delta":{"type":"input_json_delta","partial_json":"{\"comm"}}}
    """#))
    #expect(out.events == [.toolInputDelta(blockIndex: 2, partialJSON: "{\"comm")])
}

/// D7: a assinatura do bloco de raciocínio não tem nada a mostrar delta a
/// delta; ela chega inteira no `raw` do bloco consolidado.
@Test func aSignatureDeltaProducesNothing() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"stream_event","event":{"type":"content_block_delta","index":1,
     "delta":{"type":"signature_delta","signature":"abc"}}}
    """#))
    #expect(out == .empty)
}

@Test func messageStartBecomesTurnStarted() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"stream_event","event":{"type":"message_start",
     "message":{"model":"claude-opus-5","content":[]}}}
    """#))
    #expect(out.events == [.turnStarted])
    #expect(out.entries.isEmpty)
}

/// Os quadros de moldura do stream não interessam a ninguém: o começo e o fim
/// de bloco a UI infere do índice dos deltas, e o fim de mensagem chega
/// consolidado na linha `assistant`.
@Test func theStreamFramingEventsProduceNothing() throws {
    for frame in [
        #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
        #"{"type":"content_block_stop","index":0}"#,
        #"{"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#,
        #"{"type":"message_stop"}"#,
    ] {
        let out = makeMapper().map(try json(#"{"type":"stream_event","event":\#(frame)}"#))
        #expect(out == .empty, "quadro inesperadamente mapeado: \(frame)")
    }
}

/// D1, o invariante que este plano existe para garantir: o fluxo de deltas
/// NUNCA alimenta o transcript. São 298 `stream_event` contra 17 `assistant`
/// no corpus — se os dois alimentassem, todo turno apareceria centenas de
/// vezes no store.
@Test func noStreamEventEverProducesADurableEntry() throws {
    let malformed = [
        #"{"type":"stream_event"}"#,
        #"{"type":"stream_event","event":{}}"#,
        #"{"type":"stream_event","event":{"type":"content_block_delta"}}"#,
        #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta"}}}"#,
        #"{"type":"stream_event","event":{"type":"algo_novo"}}"#,
    ]
    for line in malformed {
        #expect(try makeMapper().map(json(line)).entries.isEmpty, "linha: \(line)")
    }
}

// MARK: - Degradação

@Test func anUnknownLineTypeIsPreservedNotDropped() throws {
    let line = try json(#"{"type":"future_thing","payload":{"a":1}}"#)
    let out = makeMapper().map(line)
    #expect(out.events.isEmpty)
    let entry = try #require(out.entries.first)
    #expect(out.entries.count == 1)
    #expect(entry.kind == .unrecognized(discriminator: "claude:future_thing", payload: line))
    #expect(entry.raw == line)
    #expect(entry.timestamp == fixedNow)
}

@Test func aLineWithoutATypeIsPreservedToo() throws {
    let line = try json(#"{"sem":"tipo"}"#)
    let entry = try #require(makeMapper().map(line).entries.first)
    #expect(entry.kind == .unrecognized(discriminator: "claude:line", payload: line))
}

@Test func aLineThatIsNotJSONIsPreservedAsText() {
    let out = makeMapper().map(line: Data("isto não é json".utf8))
    #expect(out.entries.count == 1)
    #expect(out.entries.first?.kind
            == .unrecognized(discriminator: "claude:nonJSON", payload: .string("isto não é json")))
}

/// O prefixo é o que impede um `"type":"turnResult"` futuro de virar um
/// discriminador que um leitor confunde com o caso conhecido `turnResult` —
/// ver a nota da task.
@Test func theDiscriminatorNeverCollidesWithAKnownKind() throws {
    let line = try json(#"{"type":"turnResult"}"#)
    guard case .unrecognized(let discriminator, _) =
            try #require(makeMapper().map(line).entries.first).kind else {
        Issue.record("esperava .unrecognized"); return
    }
    #expect(discriminator == "claude:turnResult")
    #expect(!TranscriptEntry.Kind.knownDiscriminators.contains(discriminator))
}

@Test func aControlFrameProducesNothingBecauseTheControlChannelOwnsIt() throws {
    #expect(try makeMapper().map(json(#"{"type":"control_request","request_id":"1"}"#)) == .empty)
    #expect(try makeMapper().map(json(#"{"type":"control_response","response":{}}"#)) == .empty)
}

// MARK: - Durável: assistant

@Test func anAssistantTextBlockBecomesOneDurableEntryAndNoEvent() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"assistant","timestamp":"2026-09-17T02:16:56.133Z",
     "message":{"role":"assistant","content":[{"type":"text","text":"OK"}]}}
    """#))
    #expect(out.events.isEmpty)
    #expect(out.entries.count == 1)
    #expect(out.entries[0].kind == .assistantText("OK"))
    // D4: o `raw` de uma entrada derivada de bloco é o bloco.
    #expect(out.entries[0].raw == .object(["type": .string("text"), "text": .string("OK")]))
}

/// A linha traz `timestamp` próprio — o relógio injetado não é usado.
@Test func anAssistantEntryUsesTheLineTimestamp() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"assistant","timestamp":"2026-09-17T02:20:59.447Z",
     "message":{"content":[{"type":"text","text":"x"}]}}
    """#))
    // Tolerância, não igualdade: `Date` compara `Double`, e o valor que sai
    // do parser não é bit a bit o mesmo que o literal. Isto afere a análise do
    // carimbo, não o relógio de parede.
    let expected = Date(timeIntervalSince1970: 1_789_611_659.447)
    #expect(abs(out.entries[0].timestamp.timeIntervalSince(expected)) < 0.001)
}

@Test func anAssistantTimestampThatDoesNotParseFallsBackToTheClock() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"assistant","timestamp":"ontem de tarde",
     "message":{"content":[{"type":"text","text":"x"}]}}
    """#))
    #expect(out.entries[0].timestamp == fixedNow)
}

@Test func aThinkingBlockBecomesAssistantThinking() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"assistant","message":{"content":[
      {"type":"thinking","thinking":"deixa eu ver","signature":"abc"}]}}
    """#))
    #expect(out.entries.count == 1)
    #expect(out.entries[0].kind == .assistantThinking("deixa eu ver"))
    // A assinatura sobrevive no raw, que é o que o D7 prometeu.
    #expect(out.entries[0].raw["signature"]?.stringValue == "abc")
}

@Test func aToolUseBlockBecomesAToolCallWithItsCanonicalVerb() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"assistant","message":{"content":[
      {"type":"tool_use","id":"toolu_1","name":"Bash",
       "input":{"command":"ls","description":"listar"}}]}}
    """#))
    guard case .toolCall(let call) = try #require(out.entries.first).kind else {
        Issue.record("esperava .toolCall"); return
    }
    #expect(call.id == "toolu_1")
    #expect(call.rawName == "Bash")
    #expect(call.canonical == .execute)
    #expect(call.input["command"]?.stringValue == "ls")
}

@Test func aToolWithoutACanonicalVerbKeepsItsRawName() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"assistant","message":{"content":[
      {"type":"tool_use","id":"toolu_2","name":"Skill","input":{}}]}}
    """#))
    guard case .toolCall(let call) = try #require(out.entries.first).kind else {
        Issue.record("esperava .toolCall"); return
    }
    #expect(call.canonical == nil)
    #expect(call.rawName == "Skill")
}

@Test func aMessageWithSeveralBlocksBecomesOneEntryPerBlockInOrder() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"assistant","message":{"content":[
      {"type":"thinking","thinking":"hm"},
      {"type":"text","text":"vou listar"},
      {"type":"tool_use","id":"t1","name":"Bash","input":{}}]}}
    """#))
    #expect(out.entries.count == 3)
    #expect(out.entries[0].kind == .assistantThinking("hm"))
    #expect(out.entries[1].kind == .assistantText("vou listar"))
    if case .toolCall = out.entries[2].kind {} else { Issue.record("esperava .toolCall em 2") }
}

/// Spec §5.4: nenhum bloco é descartado, nem o que não sabemos ler.
@Test func anUnknownOrMalformedBlockIsPreservedNotDropped() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"assistant","message":{"content":[
      {"type":"bloco_novo","seja_o_que_for":1},
      {"type":"text"},
      {"sem":"tipo"}]}}
    """#))
    #expect(out.entries.count == 3)
    for entry in out.entries {
        guard case .unrecognized(let discriminator, _) = entry.kind else {
            Issue.record("esperava .unrecognized, veio \(entry.kind)"); continue
        }
        #expect(discriminator.hasPrefix("claude:content/"))
    }
}

@Test func anAssistantLineWithoutContentIsPreservedWhole() throws {
    let line = try json(#"{"type":"assistant","message":{"role":"assistant"}}"#)
    let entry = try #require(makeMapper().map(line).entries.first)
    #expect(entry.kind == .unrecognized(discriminator: "claude:assistant", payload: line))
}

// MARK: - Durável: user

@Test func aToolResultBlockBecomesAToolResultEntry() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"user","timestamp":"2026-09-17T02:20:59.447Z","message":{"role":"user","content":[
      {"type":"tool_result","tool_use_id":"toolu_1","content":"total 16","is_error":false}]}}
    """#))
    guard case .toolResult(let result) = try #require(out.entries.first).kind else {
        Issue.record("esperava .toolResult"); return
    }
    #expect(result.callID == "toolu_1")
    #expect(result.isError == false)
    #expect(result.content.stringValue == "total 16")
}

/// `is_error` chega ausente em parte das linhas do corpus. Ausente significa
/// "deu certo" — não "não sabemos".
@Test func aToolResultWithoutIsErrorIsNotAnError() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"user","message":{"content":[
      {"type":"tool_result","tool_use_id":"t","content":"ok"}]}}
    """#))
    guard case .toolResult(let result) = try #require(out.entries.first).kind else {
        Issue.record("esperava .toolResult"); return
    }
    #expect(result.isError == false)
}

@Test func aFailedToolResultCarriesItsErrorFlag() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"user","message":{"content":[
      {"type":"tool_result","tool_use_id":"t","content":"blocked","is_error":true}]}}
    """#))
    guard case .toolResult(let result) = try #require(out.entries.first).kind else {
        Issue.record("esperava .toolResult"); return
    }
    #expect(result.isError == true)
}

/// Forma sintética: o CLI observado não ecoa o turno que escrevemos. Ver a
/// nota da task.
@Test func aUserLineWithStringContentBecomesAUserMessage() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"user","message":{"role":"user","content":"liste a pasta"}}
    """#))
    #expect(out.entries.count == 1)
    #expect(out.entries[0].kind == .userMessage(text: "liste a pasta", attachments: []))
}

// MARK: - Durável: result

@Test func aResultLineBecomesATurnResultWithItsUsage() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"result","subtype":"success","is_error":false,"stop_reason":"end_turn",
     "result":"OK","total_cost_usd":0.133027,
     "usage":{"input_tokens":2,"output_tokens":4,
              "cache_read_input_tokens":0,"cache_creation_input_tokens":13197}}
    """#))
    #expect(out.events.isEmpty)
    #expect(out.entries.count == 1)
    guard case .turnResult(let turn) = out.entries[0].kind else {
        Issue.record("esperava .turnResult"); return
    }
    #expect(turn.usage == UsageTotals(inputTokens: 2, outputTokens: 4,
                                      cacheReadTokens: 0, cacheCreationTokens: 13197,
                                      costUSD: 0.133027))
    #expect(turn.stopReason == "end_turn")
    #expect(turn.isError == false)
    // A linha não traz timestamp: vale o relógio injetado.
    #expect(out.entries[0].timestamp == fixedNow)
}

/// D3: a prosa final da linha `result` é a MESMA do último bloco `text` da
/// linha `assistant`. Mapeá-la duplicaria o último parágrafo de todo turno.
@Test func theFinalProseIsNotDuplicatedAsAssistantText() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"result","is_error":false,"result":"OK","usage":{}}
    """#))
    #expect(out.entries.count == 1)
    for entry in out.entries {
        if case .assistantText = entry.kind { Issue.record("prosa final duplicada") }
    }
    // Mas continua recuperável: o raw guarda a linha inteira.
    #expect(out.entries[0].raw["result"]?.stringValue == "OK")
}

@Test func aResultWithoutUsageCountsZeroInsteadOfFailing() throws {
    let out = makeMapper().map(try json(#"{"type":"result","is_error":true}"#))
    guard case .turnResult(let turn) = try #require(out.entries.first).kind else {
        Issue.record("esperava .turnResult"); return
    }
    #expect(turn.usage == .zero)
    #expect(turn.isError == true)
    #expect(turn.stopReason == nil)
}

// MARK: - Linhas de sistema

@Test func systemInitAnnouncesTheModelAndAlsoLandsInTheTranscript() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"system","subtype":"init","model":"claude-opus-5",
     "session_id":"cf77236a-23fd-43ad-95ed-a5ea2792daba","cwd":"/tmp","tools":["Bash"]}
    """#))
    #expect(out.events == [.sessionInitialized(model: "claude-opus-5",
                                               harnessSessionID: "cf77236a-23fd-43ad-95ed-a5ea2792daba")])
    #expect(out.entries.count == 1)
    #expect(out.entries[0].kind == .systemNotice(subtype: "init", text: "claude-opus-5"))
    // D4: entrada derivada da linha carrega a linha inteira.
    #expect(out.entries[0].raw["cwd"]?.stringValue == "/tmp")
}

/// D2: 21 das 30 linhas `system` do corpus são progresso de exibição. Elas vão
/// para a UI e morrem ali — o transcript é registro semântico, não log de
/// exibição (spec §4.2).
@Test func statusAndThinkingTokensAreEphemeralOnly() throws {
    let status = makeMapper().map(try json(#"""
    {"type":"system","subtype":"status","status":"Analisando","session_id":"s"}
    """#))
    #expect(status.events == [.notice(subtype: "status", text: "Analisando")])
    #expect(status.entries.isEmpty)

    let thinking = makeMapper().map(try json(#"""
    {"type":"system","subtype":"thinking_tokens","estimated_tokens":1024,
     "estimated_tokens_delta":32,"session_id":"s"}
    """#))
    #expect(thinking.events == [.notice(subtype: "thinking_tokens", text: "1024")])
    #expect(thinking.entries.isEmpty)
}

@Test func permissionDeniedIsADecisionNotANotice() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"system","subtype":"permission_denied","tool_name":"Bash",
     "tool_use_id":"toolu_01MY","message":"Output redirection was blocked.","session_id":"s"}
    """#))
    #expect(out.events.isEmpty)
    #expect(out.entries.count == 1)
    #expect(out.entries[0].kind == .permissionDecision(
        requestID: "toolu_01MY",
        .deny(message: "Output redirection was blocked.", interrupt: false)))
}

@Test func aPermissionDeniedWithoutAToolUseIDIsPreservedNotGuessed() throws {
    let line = try json(#"{"type":"system","subtype":"permission_denied","message":"x"}"#)
    let entry = try #require(makeMapper().map(line).entries.first)
    #expect(entry.kind == .unrecognized(discriminator: "claude:system/permission_denied", payload: line))
}

@Test func anUnknownSystemSubtypeIsPreserved() throws {
    let line = try json(#"{"type":"system","subtype":"algo_novo","campo":1}"#)
    let entry = try #require(makeMapper().map(line).entries.first)
    #expect(entry.kind == .unrecognized(discriminator: "claude:system/algo_novo", payload: line))
}

@Test func aSystemLineWithoutASubtypeIsPreserved() throws {
    let line = try json(#"{"type":"system","campo":1}"#)
    let entry = try #require(makeMapper().map(line).entries.first)
    #expect(entry.kind == .unrecognized(discriminator: "claude:system", payload: line))
}

/// Durável: é o que explica um turno que parou.
@Test func aRateLimitEventLandsInTheTranscript() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"rate_limit_event","rate_limit_info":{"status":"allowed","resetsAt":1789617600,
     "rateLimitType":"five_hour","isUsingOverage":false},"session_id":"s"}
    """#))
    #expect(out.events.isEmpty)
    #expect(out.entries.count == 1)
    #expect(out.entries[0].kind == .systemNotice(subtype: "rate_limit", text: "allowed"))
    #expect(out.entries[0].raw["rate_limit_info"]?["rateLimitType"]?.stringValue == "five_hour")
}

// MARK: - Entradas de permissão

@Test func aPermissionRequestBecomesAnEntryWithItsSuggestions() throws {
    let raw = try json(#"""
    {"type":"control_request","request_id":"req-1","request":{"subtype":"can_use_tool",
     "tool_name":"Write","tool_use_id":"toolu_9"}}
    """#)
    let request = PermissionRequest(
        id: "req-1",
        toolName: "Write",
        displayName: "Write",
        input: .object(["file_path": .string("/tmp/a.txt")]),
        toolUseID: "toolu_9",
        suggestions: [PermissionSuggestion(type: "addRules", mode: "acceptEdits")]
    )
    let entry = makeMapper().entry(for: request, raw: raw)
    #expect(entry.timestamp == fixedNow)
    #expect(entry.raw == raw)
    guard case .permissionRequest(let stored) = entry.kind else {
        Issue.record("esperava .permissionRequest"); return
    }
    #expect(stored == request)
    #expect(stored.suggestions.count == 1)
}

@Test func aPermissionDecisionBecomesAnEntryKeyedByTheRequestID() {
    let entry = makeMapper().entry(
        for: .allow(updatedInput: nil), requestID: "req-1", raw: .null)
    #expect(entry.kind == .permissionDecision(requestID: "req-1", .allow(updatedInput: nil)))
    #expect(entry.timestamp == fixedNow)
}
