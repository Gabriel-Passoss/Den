import Testing
import Foundation
import HarnessCore
@testable import ClaudeHarness

@Test func oStatusDeCompactandoViraFaseDeCompactacao() {
    let line: JSONValue = .object([
        "type": .string("system"),
        "subtype": .string("status"),
        "status": .string("compacting"),
        "session_id": .string("abc"),
    ])

    #expect(ClaudeEventMapper().map(line).events == [.compaction(.started)])
}

@Test func umStatusComumSegueSendoRecado() {
    let line: JSONValue = .object([
        "type": .string("system"),
        "subtype": .string("status"),
        "status": .string("requesting"),
    ])

    #expect(ClaudeEventMapper().map(line).events
            == [.notice(subtype: "status", text: "requesting")])
}

@Test func aCompactacaoQueFalhaChegaComOMotivo() {
    let line: JSONValue = .object([
        "type": .string("system"),
        "subtype": .string("status"),
        "status": .null,
        "compact_result": .string("failed"),
        "compact_error": .string("Not enough messages to compact."),
    ])

    #expect(ClaudeEventMapper().map(line).events
            == [.compaction(.failed(reason: "Not enough messages to compact."))])
}

@Test func aFronteiraDeCompactacaoGuardaOsNumeros() throws {
    let line: JSONValue = .object([
        "type": .string("system"),
        "subtype": .string("compact_boundary"),
        "compact_metadata": .object([
            "trigger": .string("manual"),
            "pre_tokens": .int(875_602),
            "post_tokens": .int(14_144),
            "duration_ms": .int(132_877),
        ]),
    ])

    let out = ClaudeEventMapper().map(line)
    #expect(out.events.isEmpty)
    guard case .contextCompacted(let compaction) = out.entries.first?.kind else {
        Issue.record("the boundary did not become a compaction entry")
        return
    }
    #expect(compaction.trigger == .manual)
    #expect(compaction.tokensBefore == 875_602)
    #expect(compaction.tokensAfter == 14_144)
    #expect(compaction.duration == 132.877)
}

@Test func aCompactacaoAutomaticaSeDistingueDaManual() throws {
    let line: JSONValue = .object([
        "type": .string("system"),
        "subtype": .string("compact_boundary"),
        "compact_metadata": .object(["trigger": .string("auto")]),
    ])

    guard case .contextCompacted(let compaction)
            = ClaudeEventMapper().map(line).entries.first?.kind else {
        Issue.record("the boundary did not become a compaction entry")
        return
    }
    #expect(compaction.trigger == .automatic)
    #expect(compaction.tokensBefore == 0)
}

@Test func aCompactacaoSobreviveAoDiscoParaVoltarNoHistorico() throws {
    let entry = TranscriptEntry(
        timestamp: Date(timeIntervalSince1970: 1),
        kind: .contextCompacted(ContextCompaction(
            trigger: .manual, tokensBefore: 875_602, tokensAfter: 14_144,
            duration: 132.877)),
        raw: .null)

    let data = try JSONEncoder().encode(entry)
    let back = try JSONDecoder().decode(TranscriptEntry.self, from: data)

    #expect(back.kind == entry.kind)
}
