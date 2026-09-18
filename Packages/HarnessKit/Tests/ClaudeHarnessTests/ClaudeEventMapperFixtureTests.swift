import Testing
import Foundation
import HarnessCore
@testable import ClaudeHarness

private let clock = Date(timeIntervalSince1970: 1_000_000)

private func mapFixture(_ name: String) throws -> MappedOutput {
    let url = try #require(Bundle.module.url(
        forResource: "Fixtures/\(name)", withExtension: "ndjson"))
    let mapper = ClaudeEventMapper(now: { clock })
    var all = MappedOutput.empty
    for line in try String(contentsOf: url, encoding: .utf8)
        .split(separator: "\n") where !line.isEmpty {
        let out = mapper.map(line: Data(line.utf8))
        all.events += out.events
        all.entries += out.entries
    }
    return all
}

private func kindName(_ kind: TranscriptEntry.Kind) -> String {
    switch kind {
    case .userMessage: return "userMessage"
    case .assistantText: return "assistantText"
    case .assistantThinking: return "assistantThinking"
    case .toolCall: return "toolCall"
    case .toolResult: return "toolResult"
    case .permissionRequest: return "permissionRequest"
    case .permissionDecision: return "permissionDecision"
    case .systemNotice: return "systemNotice"
    case .turnResult: return "turnResult"
    case .unrecognized(let discriminator, _): return "unrecognized(\(discriminator))"
    }
}

/// As contagens medidas. Um desacordo aqui é entre o mapeador e o protocolo
/// real — não ajuste o número sem olhar a fixture.
@Test(arguments: [
    ("hello", 4, 5),
    ("tool-use", 6, 42),
    ("permission-request", 6, 1),
    ("permission-denied", 27, 220),
])
func everyFixtureMapsToTheMeasuredCounts(
    fixture: (name: String, entries: Int, events: Int)
) throws {
    let out = try mapFixture(fixture.name)
    #expect(out.entries.count == fixture.entries)
    #expect(out.events.count == fixture.events)
}

/// **O teste que este plano existe para escrever.** 289 linhas, das quais 194
/// são deltas de token carregando o MESMO texto que as linhas `assistant`
/// consolidadas — e 27 entradas no transcript. Se as duas fontes alimentassem
/// o durável, este número estaria nas centenas e todo turno apareceria
/// repetido no store (spec §4.4).
@Test func theDeltaStreamNeverReachesTheTranscript() throws {
    let out = try mapFixture("permission-denied")
    #expect(out.entries.count == 27)
    #expect(out.events.count == 220)

    let texts = out.entries.compactMap { entry -> String? in
        guard case .assistantText(let text) = entry.kind else { return nil }
        return text
    }
    #expect(texts.count == 1, "um texto consolidado por turno, não um por delta")
}

/// A sequência conta a história: o assistente chama a ferramenta, o harness
/// nega, a ferramenta devolve erro, o assistente raciocina — seis vezes.
@Test func theOrderOfKindsPreservesTheStory() throws {
    let kinds = try mapFixture("permission-denied").entries.map { kindName($0.kind) }
    #expect(kinds == [
        "systemNotice", "systemNotice",
        "toolCall", "permissionDecision", "toolResult", "assistantThinking",
        "toolCall", "permissionDecision", "toolResult", "assistantThinking",
        "toolCall", "permissionDecision", "toolResult", "assistantThinking",
        "toolCall", "permissionDecision", "toolResult", "assistantThinking",
        "toolCall", "permissionDecision", "toolResult", "assistantThinking",
        "toolCall", "permissionDecision", "toolResult",
        "assistantText", "turnResult",
    ])
}

@Test(arguments: ["hello", "tool-use", "permission-request", "permission-denied"])
func theHappyPathFixturesShareTheSameSpine(name: String) throws {
    let kinds = try mapFixture(name).entries.map { kindName($0.kind) }
    #expect(kinds.first == "systemNotice", "toda sessão abre com um system/init")
    #expect(kinds.last == "turnResult", "e fecha com o result do turno")
}

/// Cobertura do protocolo observado: se o mapeador conhece tudo que este CLI
/// emite, nenhuma linha do corpus degrada. Uma `unrecognized` aqui é uma
/// forma que o plano não previu — e a mensagem diz qual.
@Test(arguments: ["hello", "tool-use", "permission-request", "permission-denied"])
func noFixtureLineDegrades(name: String) throws {
    for entry in try mapFixture(name).entries {
        if case .unrecognized(let discriminator, _) = entry.kind {
            Issue.record("\(name): forma não prevista \(discriminator)")
        }
    }
}

/// Fidelidade referencial (spec §4.2): todo resultado de ferramenta aponta
/// para uma chamada que está no mesmo transcript. Sem isso o replay entrega
/// ao próximo harness uma resposta para uma pergunta que ele nunca viu.
@Test(arguments: ["tool-use", "permission-request", "permission-denied"])
func everyToolResultPointsAtAToolCallInTheSameTranscript(name: String) throws {
    let entries = try mapFixture(name).entries
    let callIDs = Set(entries.compactMap { entry -> String? in
        guard case .toolCall(let call) = entry.kind else { return nil }
        return call.id
    })
    #expect(!callIDs.isEmpty)
    for entry in entries {
        guard case .toolResult(let result) = entry.kind else { continue }
        #expect(callIDs.contains(result.callID), "resultado órfão: \(result.callID)")
    }
}

/// E o mesmo para as decisões de permissão: o `requestID` de uma negação é o
/// `tool_use_id` da chamada que foi barrada.
@Test func everyDenialPointsAtTheCallItBlocked() throws {
    let entries = try mapFixture("permission-denied").entries
    let callIDs = Set(entries.compactMap { entry -> String? in
        guard case .toolCall(let call) = entry.kind else { return nil }
        return call.id
    })
    var decisions = 0
    for entry in entries {
        guard case .permissionDecision(let requestID, let decision) = entry.kind else { continue }
        decisions += 1
        #expect(callIDs.contains(requestID), "negação órfã: \(requestID)")
        guard case .deny = decision else { Issue.record("esperava .deny"); continue }
    }
    #expect(decisions == 6)
}

/// A saída do mapeador tem que ser gravável: a `.unrecognized` tem contrato de
/// idempotência e os `raw` são JSON arbitrário vindo do fio. Este teste leva o
/// corpus inteiro até o disco e de volta.
@Test func theMappedTranscriptSurvivesTheStore() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mapper-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let entries = try mapFixture("permission-denied").entries
    let segment = Segment(harness: .claudeCode, harnessSessionID: UUID(), model: "claude-opus-5")
    let session = Session(title: "corpus", workingDirectory: root, segments: [segment])

    let store = FileTranscriptStore(root: root)
    try await store.saveMetadata(session)
    for entry in entries {
        try await store.append(entry, to: segment.id, in: session.id)
    }

    let loaded = try await store.load(session.id)
    #expect(loaded.allEntries.count == entries.count)
    #expect(loaded.allEntries.map(\.kind) == entries.map(\.kind))
    #expect(loaded.allEntries.map(\.raw) == entries.map(\.raw))
    #expect(loaded.allEntries.map(\.id) == entries.map(\.id))

    // Os carimbos NÃO são comparados por igualdade, e a razão é um achado:
    // o store codifica datas com `.iso8601`, que não escreve fração de
    // segundo. As linhas `assistant` e `user` trazem milissegundos
    // ("…:59.447Z"), então um carimbo que vai ao disco volta truncado no
    // segundo. Não é erro de ordenação — a ordem do transcript é a ordem de
    // append no NDJSON, não a do carimbo —, mas é perda de fidelidade, e está
    // anotada como pendência ao fim deste plano.
    for (loadedEntry, original) in zip(loaded.allEntries, entries) {
        #expect(abs(loadedEntry.timestamp.timeIntervalSince(original.timestamp)) < 1)
    }
}
