import Testing
import Foundation
@testable import HarnessCore

// Id neutro, mesmo padrão de FileTranscriptStoreTests.swift: `HarnessID.claudeCode`
// mora em `ClaudeHarness` (spec §7.1; `harnessCoreNeverNamesASpecificHarness` em
// ModuleBoundaryTests.swift), e este alvo de teste não depende de `ClaudeHarness`.
private let harnessA = HarnessID(rawValue: "harness-a")

private let when = Date(timeIntervalSince1970: 1_700_000_000)

private func makeRoot() throws -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("resilience-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func entry(_ text: String) -> TranscriptEntry {
    TranscriptEntry(timestamp: when, kind: .assistantText(text), raw: .null)
}

@Test func aTruncatedLastLineCostsOneEntryNotTheWholeSession() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let segment = Segment(harness: harnessA, harnessSessionID: UUID(), model: "m")
    let session = Session(title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
                          segments: [segment])
    try await store.saveMetadata(session)
    try await store.append(entry("um"), to: segment.id, in: session.id)
    try await store.append(entry("dois"), to: segment.id, in: session.id)

    // Simula o processo morto no meio de uma escrita.
    let file = root.appendingPathComponent(session.id.uuidString)
        .appendingPathComponent("\(segment.id.uuidString).ndjson")
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(#"{"id":"não termi"#.utf8))
    try handle.close()

    let loaded = try await store.load(session.id)
    let texts = loaded.allEntries.compactMap { e -> String? in
        if case .assistantText(let t) = e.kind { return t }
        return nil
    }
    #expect(texts == ["um", "dois"], "meia linha não pode custar a conversa inteira")
}

@Test func aCorruptLineInTheMiddleDoesNotHideTheOnesAfterIt() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let segment = Segment(harness: harnessA, harnessSessionID: UUID(), model: "m")
    let session = Session(title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
                          segments: [segment])
    try await store.saveMetadata(session)
    try await store.append(entry("um"), to: segment.id, in: session.id)

    let file = root.appendingPathComponent(session.id.uuidString)
        .appendingPathComponent("\(segment.id.uuidString).ndjson")
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("{lixo}\n".utf8))
    try handle.close()
    try await store.append(entry("tres"), to: segment.id, in: session.id)

    let loaded = try await store.load(session.id)
    let texts = loaded.allEntries.compactMap { e -> String? in
        if case .assistantText(let t) = e.kind { return t }
        return nil
    }
    #expect(texts == ["um", "tres"])
}

@Test func aTruncatedTailDoesNotSwallowTheEntryAppendedAfterARestart() async throws {
    // O processo morre no meio da escrita de "dois": a última linha fica sem
    // `\n` final. O app reinicia e resume o MESMO segmento (spec §5.1: idle
    // → hot é `--resume` da mesma harness session) — reabre o mesmo arquivo
    // e dá append de novo. Sem uma guarda de newline, `O_APPEND` escreve os
    // bytes novos GRUDADOS no fragmento truncado, e a entrada nova ("tres"),
    // completa e íntegra, é arrastada para dentro do blob ilegível e
    // perdida junto com "dois" — que essa, sim, já estava perdida por
    // direito.
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let segment = Segment(harness: harnessA, harnessSessionID: UUID(), model: "m")
    let session = Session(title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
                          segments: [segment])
    try await store.saveMetadata(session)
    try await store.append(entry("um"), to: segment.id, in: session.id)

    let file = root.appendingPathComponent(session.id.uuidString)
        .appendingPathComponent("\(segment.id.uuidString).ndjson")
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(#"{"id":"partial"#.utf8))
    try handle.close()

    try await store.append(entry("tres"), to: segment.id, in: session.id)

    let loaded = try await store.load(session.id)
    let texts = loaded.allEntries.compactMap { e -> String? in
        if case .assistantText(let t) = e.kind { return t }
        return nil
    }
    #expect(texts == ["um", "tres"],
             "a entrada nova não pode ser perdida junto com o fragmento truncado")
}

@Test func listCountsRawLinesWhileLoadCountsDecodableEntries() async throws {
    // `list()` conta linhas em disco (barato, sem decodificar); `load()`
    // conta entradas que decodificaram. Sobre bytes danificados os dois
    // números legitimamente discordam: a fatia truncada existe no arquivo
    // (`split` a inclui mesmo sem `\n` final) mas não decodifica. A
    // divergência é documentada em `FileTranscriptStore.list()` e
    // `entries(of:in:)` — este teste fixa o número exato para que uma
    // mudança futura em qualquer um dos dois lados não passe despercebida.
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let segment = Segment(harness: harnessA, harnessSessionID: UUID(), model: "m")
    let session = Session(title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
                          segments: [segment])
    try await store.saveMetadata(session)
    try await store.append(entry("um"), to: segment.id, in: session.id)
    try await store.append(entry("dois"), to: segment.id, in: session.id)

    let file = root.appendingPathComponent(session.id.uuidString)
        .appendingPathComponent("\(segment.id.uuidString).ndjson")
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(#"{"id":"partial"#.utf8))
    try handle.close()

    let summaries = try await store.list()
    let loaded = try await store.load(session.id)

    #expect(summaries.first?.entryCount == 3,
             "list() conta a linha truncada como uma linha em disco")
    #expect(loaded.allEntries.count == 2,
             "load() só conta o que de fato decodificou")
}

@Test func aSegmentWithNoFileYetLoadsAsEmpty() async throws {
    // Um segmento recém-aberto ainda não tem arquivo. Isso é normal, não erro.
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let segment = Segment(harness: harnessA, harnessSessionID: UUID(), model: "m")
    let session = Session(title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
                          segments: [segment])
    try await store.saveMetadata(session)

    let loaded = try await store.load(session.id)
    #expect(loaded.segments.first?.entries.isEmpty == true)
}

@Test func loadingAnUnknownSessionSaysSoInsteadOfCrashing() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)
    let missing = UUID()
    await #expect(throws: FileTranscriptStore.StoreError.sessionNotFound(missing)) {
        _ = try await store.load(missing)
    }
}

@Test func listSkipsADirectoryWithoutValidMetadata() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let good = Session(title: "boa", workingDirectory: URL(fileURLWithPath: "/tmp"), segments: [])
    try await store.saveMetadata(good)

    let junk = root.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: junk, withIntermediateDirectories: true)
    try Data("{não sou json".utf8).write(to: junk.appendingPathComponent("session.json"))
    try FileManager.default.createDirectory(
        at: root.appendingPathComponent("nem-diretorio-de-sessao"),
        withIntermediateDirectories: true)

    let summaries = try await store.list()
    #expect(summaries.map(\.id) == [good.id])
}

@Test func listOnAnEmptyOrMissingRootIsEmptyNotAnError() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(try await FileTranscriptStore(root: root).list().isEmpty)

    let missing = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("nao-existe-\(UUID().uuidString)")
    #expect(try await FileTranscriptStore(root: missing).list().isEmpty)
}
