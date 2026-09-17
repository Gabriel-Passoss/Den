import Testing
import Foundation
@testable import HarnessCore
import HarnessTestSupport

// Dois ids neutros, mesmo padrão de SessionTests.swift: `HarnessID.claudeCode`
// mora em `ClaudeHarness` (spec §7.1; `harnessCoreNeverNamesASpecificHarness`
// em ModuleBoundaryTests.swift), e este alvo de teste não depende de
// `ClaudeHarness`.
private let harnessA = HarnessID(rawValue: "harness-a")
private let harnessB = HarnessID(rawValue: "harness-b")

private let when = Date(timeIntervalSince1970: 1_700_000_000)

private func makeRoot() throws -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("transcript-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func entry(_ text: String) -> TranscriptEntry {
    TranscriptEntry(timestamp: when, kind: .assistantText(text), raw: .object(["t": .string(text)]))
}

private func newSession(segments: [Segment]) -> Session {
    Session(title: "uma conversa", workingDirectory: URL(fileURLWithPath: "/tmp/repo"),
            segments: segments)
}

private func newSegment(_ harness: HarnessID = harnessA) -> Segment {
    Segment(harness: harness, harnessSessionID: UUID(), model: "m")
}

@Test func aSessionRoundTripsThroughDisk() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let segment = newSegment()
    let session = newSession(segments: [segment])
    try await store.saveMetadata(session)
    try await store.append(entry("um"), to: segment.id, in: session.id)
    try await store.append(entry("dois"), to: segment.id, in: session.id)

    let loaded = try await store.load(session.id)
    #expect(loaded.id == session.id)
    #expect(loaded.title == "uma conversa")
    #expect(loaded.workingDirectory.path == "/tmp/repo")
    #expect(loaded.segments.count == 1)
    let texts = loaded.allEntries.compactMap { e -> String? in
        if case .assistantText(let t) = e.kind { return t }
        return nil
    }
    #expect(texts == ["um", "dois"])
}

@Test func theRawPayloadSurvivesDisk() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)
    let segment = newSegment()
    let session = newSession(segments: [segment])
    try await store.saveMetadata(session)
    try await store.append(entry("x"), to: segment.id, in: session.id)

    let loaded = try await store.load(session.id)
    #expect(loaded.allEntries.first?.raw["t"] == .string("x"))
}

@Test func entriesFromDifferentSegmentsDoNotMix() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let first = newSegment(harnessA)
    let second = newSegment(harnessB)
    let session = newSession(segments: [first, second])
    try await store.saveMetadata(session)
    try await store.append(entry("claude-um"), to: first.id, in: session.id)
    try await store.append(entry("codex-um"), to: second.id, in: session.id)
    try await store.append(entry("claude-dois"), to: first.id, in: session.id)

    let loaded = try await store.load(session.id)
    #expect(loaded.segments[0].entries.count == 2)
    #expect(loaded.segments[1].entries.count == 1)
    #expect(loaded.segments[1].harness == harnessB)
}

@Test func theFileOnDiskIsOneJSONObjectPerLine() async throws {
    // O formato tem que ser legível com `cat` quando algo der errado (spec §4.3).
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)
    let segment = newSegment()
    let session = newSession(segments: [segment])
    try await store.saveMetadata(session)
    try await store.append(entry("um"), to: segment.id, in: session.id)
    try await store.append(entry("dois"), to: segment.id, in: session.id)

    let file = root.appendingPathComponent(session.id.uuidString)
        .appendingPathComponent("\(segment.id.uuidString).ndjson")
    let lines = try String(contentsOf: file, encoding: .utf8)
        .split(separator: "\n").filter { !$0.isEmpty }
    #expect(lines.count == 2)
    for line in lines {
        #expect((try? JSONSerialization.jsonObject(with: Data(line.utf8))) != nil)
    }
}

@Test func listReturnsASummaryPerSession() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let a = newSession(segments: [newSegment()])
    let b = newSession(segments: [newSegment()])
    try await store.saveMetadata(a)
    try await store.saveMetadata(b)

    let summaries = try await store.list()
    #expect(summaries.count == 2)
    #expect(Set(summaries.map(\.id)) == Set([a.id, b.id]))
}

@Test func savingMetadataAgainDoesNotDisturbTheEntries() async throws {
    // Renomear a sessão não pode apagar o transcript.
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)
    let segment = newSegment()
    var session = newSession(segments: [segment])
    try await store.saveMetadata(session)
    try await store.append(entry("um"), to: segment.id, in: session.id)

    session.title = "outro título"
    try await store.saveMetadata(session)

    let loaded = try await store.load(session.id)
    #expect(loaded.title == "outro título")
    #expect(loaded.allEntries.count == 1)
}

@Test func appendToAMissingSessionFailsWithSessionNotFound() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)
    let missingSessionID = UUID()

    await #expect(throws: FileTranscriptStore.StoreError.sessionNotFound(missingSessionID)) {
        try await store.append(entry("um"), to: UUID(), in: missingSessionID)
    }
}

@Test func appendToASegmentNotListedInTheSessionFailsWithSegmentNotFound() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)
    let segment = newSegment()
    let session = newSession(segments: [segment])
    try await store.saveMetadata(session)

    // Um id de segmento nunca listado no session.json desta sessão — por
    // exemplo, um bug de ordenação a montante, ou um segmento removido dos
    // metadados. `append` não pode escrever silenciosamente num arquivo que
    // `load()`/`list()` nunca vão enumerar.
    let strangerSegmentID = UUID()
    await #expect(throws: FileTranscriptStore.StoreError.segmentNotFound(strangerSegmentID)) {
        try await store.append(entry("um"), to: strangerSegmentID, in: session.id)
    }
}

/// Duas instâncias deste tipo sobre o MESMO root modelam duas janelas do
/// DevSpace apontando pro mesmo diretório de transcript — ou uma janela e a
/// sonda de diagnóstico. O actor só serializa chamadas DENTRO de uma
/// instância; o arquivo em disco é o único estado que as duas compartilham.
///
/// Contra a implementação de duas rotas (`!fileExists` ? write atômico
/// baseado em rename : `seekToEnd()` + `write(contentsOf:)`), isso reproduz
/// duas corridas ao mesmo tempo: a primeira escrita de cada segmento (ambas
/// as instâncias veem o arquivo ausente, ambas fazem o write atômico — quem
/// renomeia por último vence, e a entrada da outra desaparece sem erro nos
/// dois lados) e toda escrita seguinte (seek e write são dois passos
/// separados: duas instâncias podem calcular o mesmo offset de fim-de-arquivo
/// antes que qualquer uma escreva, e a segunda escrita pisa em cima da
/// primeira). Uma linha pisada corrompe o JSON daquela linha, e
/// `entries(of:in:)` decodifica com `try` dentro de um `map` — uma linha
/// corrompida derruba o decode do SEGMENTO INTEIRO, não só das entradas em
/// disputa. A corrida se manifesta como `load()` lançando erro, ou como uma
/// contagem de entradas menor que o total esperado.
@Test func concurrentAppendsFromDifferentStoreInstancesDoNotCorruptOrLoseEntries() async throws {
    try await withTimeout(seconds: 20) {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let segment = newSegment()
        let session = newSession(segments: [segment])
        // Uma instância grava os metadados; o arquivo do segmento ainda não
        // existe — a primeira escrita concorrente também disputa a CRIAÇÃO do
        // arquivo, não só o append nele.
        try await FileTranscriptStore(root: root).saveMetadata(session)

        let storeCount = 4
        let writersPerStore = 4
        let roundsPerWriter = 10
        // Instâncias distintas de propósito: contenção entre instâncias é o
        // que este teste existe para amostrar, não contenção dentro de uma
        // instância só (essa já é serializada pelo próprio actor).
        let stores = (0..<storeCount).map { _ in FileTranscriptStore(root: root) }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for (storeIndex, store) in stores.enumerated() {
                for writerIndex in 0..<writersPerStore {
                    group.addTask {
                        for round in 0..<roundsPerWriter {
                            try await store.append(
                                entry("s\(storeIndex)-w\(writerIndex)-r\(round)"),
                                to: segment.id, in: session.id)
                        }
                    }
                }
            }
            try await group.waitForAll()
        }

        let expected = Set(
            (0..<storeCount).flatMap { storeIndex in
                (0..<writersPerStore).flatMap { writerIndex in
                    (0..<roundsPerWriter).map { round in "s\(storeIndex)-w\(writerIndex)-r\(round)" }
                }
            })

        let loaded = try await stores[0].load(session.id)
        let texts = loaded.allEntries.compactMap { e -> String? in
            if case .assistantText(let t) = e.kind { return t }
            return nil
        }
        // Nem perdida (a contagem bate) nem corrompida/duplicada (o conjunto
        // bate exatamente com o esperado — nenhum texto estranho, nenhum
        // repetido, nenhum faltando).
        #expect(texts.count == expected.count)
        #expect(Set(texts) == expected)
    }
}
