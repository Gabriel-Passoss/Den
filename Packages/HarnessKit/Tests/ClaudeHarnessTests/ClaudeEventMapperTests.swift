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
