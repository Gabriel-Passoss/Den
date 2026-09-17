import Testing
import Foundation
@testable import HarnessCore

/// O formato durável, fixado por fixtures escritas à mão.
///
/// As entradas vão para o disco como `{"kind":{"assistantText":{"_0":"olá"}}}`.
/// Essas chaves `_0`, os nomes de caso e os nomes de rótulo **são** o formato
/// de arquivo do artefato central do produto — e nada os fixava além da
/// síntese de `Codable` do próprio Swift. Todo teste que existia fazia
/// round-trip pelo mesmo par encoder/decoder, então todos concordavam entre si
/// por construção: renomear `userMessage(text:)` para `userMessage(content:)`
/// órfãnaria todo transcript em disco de todo usuário com a suíte verde.
///
/// Por isso as fixtures aqui são LITERAIS, escritas à mão. Elas não são
/// geradas pelo encoder; são o contrato contra o qual o encoder e o decoder
/// são medidos, nas duas direções:
///
/// - decodificar a fixture e comparar com o valor esperado pega um decoder que
///   mudou de forma;
/// - codificar o valor esperado e comparar com a fixture pega um encoder que
///   mudou de forma (o caso do rename, que é o perigoso: ele escreve bytes
///   novos que nenhum leitor antigo abre).
///
/// Se um destes testes falhar, a pergunta não é "como conserto o teste" — é
/// "esta mudança de formato é intencional, e os transcripts já em disco?".
/// A resposta certa é quase sempre mudar o código de volta.

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

/// Compara JSON por VALOR, não por bytes: o que está sob contrato são as
/// chaves e os valores, não a ordem em que o encoder resolve emiti-los.
private func json(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

/// Um caso de `Kind` e a linha exata que ele ocupa em disco.
private struct Golden {
    let discriminator: String
    let kind: TranscriptEntry.Kind
    let wire: String
}

/// Os nove casos conhecidos da spec §4.2, cada um com seu JSON literal.
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
        kind: .assistantText("oi"),
        wire: #"{"assistantText":{"_0":"oi"}}"#
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
                                               raw: .object(["k": .bool(true)]))])),
        wire: #"{"permissionRequest":{"_0":{"description":"d","displayName":"Escrever","id":"r1","input":{"path":"/tmp/x"},"suggestions":[{"behavior":"allow","destination":"session","mode":"acceptEdits","raw":{"k":true},"type":"setMode"}],"toolName":"Write","toolUseID":"t2"}}}"#
    ),
    // Duas linhas para `permissionDecision`: o `_1` do valor associado SEM
    // rótulo é a parte mais frágil do formato inteiro — sai de uma convenção
    // do compilador, não de nada que alguém tenha escrito.
    Golden(
        discriminator: "permissionDecision",
        kind: .permissionDecision(requestID: "r1", .allow(updatedInput: .object(["p": .string("y")]))),
        wire: #"{"permissionDecision":{"_1":{"allow":{"updatedInput":{"p":"y"}}},"requestID":"r1"}}"#
    ),
    Golden(
        discriminator: "permissionDecision",
        kind: .permissionDecision(requestID: "r2", .deny(message: "não", interrupt: true)),
        wire: #"{"permissionDecision":{"_1":{"deny":{"interrupt":true,"message":"não"}},"requestID":"r2"}}"#
    ),
    Golden(
        discriminator: "systemNotice",
        kind: .systemNotice(subtype: "init", text: "sessão iniciada"),
        wire: #"{"systemNotice":{"subtype":"init","text":"sessão iniciada"}}"#
    ),
    Golden(
        discriminator: "turnResult",
        kind: .turnResult(TurnResult(
            usage: UsageTotals(inputTokens: 10, outputTokens: 20, cacheReadTokens: 1,
                               cacheCreationTokens: 2, costUSD: 0.01),
            stopReason: "end_turn", isError: false)),
        wire: #"{"turnResult":{"_0":{"isError":false,"stopReason":"end_turn","usage":{"cacheCreationTokens":2,"cacheReadTokens":1,"costUSD":0.01,"inputTokens":10,"outputTokens":20}}}}"#
    ),
]

@Test func theNineKnownKindsDecodeFromTheirGoldenJSON() throws {
    for item in golden {
        let decoded = try decoder.decode(TranscriptEntry.Kind.self, from: Data(item.wire.utf8))
        #expect(decoded == item.kind, "o decoder mudou de forma para \(item.discriminator)")
        if case .unrecognized = decoded {
            Issue.record("\(item.discriminator) caiu no fallback — o nome de caso mudou")
        }
    }
}

@Test func theNineKnownKindsEncodeToTheirGoldenJSON() throws {
    for item in golden {
        let written = try json(String(decoding: try encoder.encode(item.kind), as: UTF8.self))
        #expect(written == (try json(item.wire)),
                "o encoder mudou de forma para \(item.discriminator) — todo transcript já em disco vira órfão")
    }
}

@Test func theGoldenFixturesCoverEveryDiscriminatorThisVersionKnows() throws {
    // Se um décimo caso REAL entrar em `Kind`, o contrato de formato tem que
    // crescer junto: uma fixture nova aqui. Sem esta asserção, o caso novo
    // ficaria sem linha dourada e o formato dele voltaria a ser "o que o
    // compilador resolver sintetizar".
    #expect(Set(golden.map(\.discriminator)) == TranscriptEntry.Kind.knownDiscriminators)
}

@Test func theEnvelopeOfATranscriptEntryIsFixedToo() throws {
    // `id`, `timestamp`, `kind`, `raw` — e a data em ISO-8601, que é decisão
    // do store e não do tipo.
    let wire = #"""
    {"id":"11111111-1111-1111-1111-111111111111","kind":{"assistantText":{"_0":"oi"}},"raw":{"a":1},"timestamp":"2023-11-14T22:13:20Z"}
    """#
    let expected = TranscriptEntry(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        timestamp: Date(timeIntervalSince1970: 1_700_000_000),
        kind: .assistantText("oi"), raw: .object(["a": .int(1)]))

    #expect(try decoder.decode(TranscriptEntry.self, from: Data(wire.utf8)) == expected)
    #expect(try json(String(decoding: try encoder.encode(expected), as: UTF8.self))
            == (try json(wire)))
}

// MARK: - Handoff: a proveniência que este plano existe para registrar

/// `Handoff.replay(throughEntry:)` não era serializado por teste nenhum —
/// o campo que carrega a proveniência inteira de uma troca de harness tinha
/// zero cobertura de encode/decode, embora viva no `session.json` de toda
/// sessão que já trocou de harness.
private let goldenHandoffs: [(String, Handoff, String)] = [
    ("briefing", .briefing("resumo"), #"{"briefing":{"_0":"resumo"}}"#),
    ("replay", .replay(throughEntry: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!),
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
    // O `seededBy` dentro do envelope do `session.json`, que é onde ele de
    // fato mora — e a razão de ser `.replay(throughEntry:)` aqui é que esse
    // caso nunca tinha sido serializado em teste nenhum.
    let wire = #"""
    {"id":"55555555-5555-5555-5555-555555555555","segments":[{"entries":[],"harness":"harness-a","harnessSessionID":"44444444-4444-4444-4444-444444444444","id":"33333333-3333-3333-3333-333333333333","model":"m","seededBy":{"replay":{"throughEntry":"22222222-2222-2222-2222-222222222222"}},"usage":{"cacheCreationTokens":0,"cacheReadTokens":0,"costUSD":0,"inputTokens":5,"outputTokens":0}}],"title":"t","workingDirectory":"file:///tmp/repo"}
    """#
    let expected = Session(
        id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
        title: "t", workingDirectory: URL(fileURLWithPath: "/tmp/repo"),
        segments: [Segment(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            harness: HarnessID(rawValue: "harness-a"),
            harnessSessionID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            model: "m", entries: [], usage: UsageTotals(inputTokens: 5),
            seededBy: .replay(throughEntry: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!))])

    let decoded = try decoder.decode(Session.self, from: Data(wire.utf8))
    #expect(decoded == expected)
    #expect(decoded.segments.first?.seededBy
            == .replay(throughEntry: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!))
    #expect(try json(String(decoding: try encoder.encode(expected), as: UTF8.self))
            == (try json(wire)))
}

// MARK: - Os dois enums abertos não podem divergir de si mesmos

/// Um caso desconhecido no `seededBy` degrada em vez de derrubar a sessão, e o
/// reencode devolve o nome original.
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

/// Mesma disciplina de escopo do `Kind`: degradar um caso desconhecido, não
/// engolir corrupção de verdade.
@Test func aHandoffThatIsNotASingleKeyedObjectStillFailsLoudly() {
    #expect(throws: (any Error).self) {
        try decoder.decode(Handoff.self, from: Data(#""briefing""#.utf8))
    }
    #expect(throws: (any Error).self) {
        try decoder.decode(Handoff.self,
                           from: Data(#"{"briefing":{"_0":"a"},"replay":{"throughEntry":"x"}}"#.utf8))
    }
}

/// O elo que o compilador NÃO fecha, fechado por um teste.
///
/// `knownDiscriminators` deixou de ser uma lista de strings mantida à mão: ele
/// é derivado de `Known.CodingKeys`, as mesmas chaves que a `Codable`
/// sintetizada de `Known` usa. E a cadeia `Kind` → `Known` → `CodingKeys` tem
/// os dois primeiros elos impostos pelo compilador (os dois `switch`
/// exaustivos de `init(from:)` e `encode(to:)`).
///
/// O terceiro elo não é — foi medido: um caso em `Known` ausente de
/// `CodingKeys` COMPILA, e só estoura em tempo de execução, no `encode`. Um
/// décimo caso REAL acrescentado com esse esquecimento escreveria bem e leria
/// de volta como `.unrecognized`: uma versão em skew contra ela mesma.
///
/// Este teste lê a própria fonte e conta os `case` declarados no corpo do
/// enum, comparando com o que `knownDiscriminators` de fato contém. Mesma
/// forma de guarda estrutural que `harnessCoreNeverNamesASpecificHarness`
/// (ModuleBoundaryTests.swift) — e escolhida em vez de uma contagem fixa
/// escrita à mão porque uma contagem fixa seria a QUARTA lista mantida à mão,
/// exatamente o problema que se quer fechar.
@Test func theOpenEnumsDoNotDivergeFromTheirKnownDiscriminators() throws {
    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // HarnessCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // HarnessKit
        .appending(path: "Sources/HarnessCore")

    // (arquivo, linha que abre o enum, linha que fecha a região de casos,
    //  discriminadores conhecidos, nome para a mensagem)
    let subjects: [(String, String, String, Set<String>, String)] = [
        ("TranscriptEntry.swift", "public enum Kind:", "private enum Known:",
         TranscriptEntry.Kind.knownDiscriminators, "TranscriptEntry.Kind"),
        ("Session.swift", "public enum Handoff:", "private enum Known:",
         Handoff.knownDiscriminators, "Handoff"),
    ]

    for (file, opening, closing, known, name) in subjects {
        let text = try String(contentsOf: sources.appending(path: file), encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let start = try #require(lines.firstIndex { $0.contains(opening) },
                                 "não achei \(opening) em \(file) — a fonte mudou de forma")
        let end = try #require(lines[start...].firstIndex { $0.contains(closing) },
                               "não achei \(closing) em \(file) — a fonte mudou de forma")
        let declared = lines[start..<end]
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("case ") }
            .count

        // `+ 1` pelo caso de fuga (`.unrecognized`), que é o único caso do
        // enum que NÃO é um discriminador conhecido.
        #expect(declared == known.count + 1,
                "\(name) declara \(declared) casos e conhece \(known.count) discriminadores — um caso novo não chegou em Known.CodingKeys")
    }
}
