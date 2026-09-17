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

private func texts(of session: Session) -> [String] {
    session.allEntries.compactMap { e -> String? in
        if case .assistantText(let t) = e.kind { return t }
        return nil
    }
}

/// - Note: o fixture desta função corta numa fronteira de caractere — por
///   acaso, `{"id":"não termi` é UTF-8 completo. Esse é o caso FÁCIL, e o
///   nome antigo ("aTruncatedLastLineCostsOneEntryNotTheWholeSession")
///   prometia o caso difícil, que ele não exercitava: um processo morto no
///   meio de uma escrita não para em fronteira de caractere. Quem cobre o
///   caso difícil é `aTailCutInsideAMultiByteCharacterCostsOneEntryNotTheWholeSession`
///   logo abaixo — e contra o código anterior este teste passava enquanto
///   aquele reprovava.
@Test func aTruncatedLastLineEndingOnACharacterBoundaryCostsOneEntry() async throws {
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

    let listing = try await store.list()
    let loaded = try await store.load(session.id)

    #expect(listing.sessions.first?.entryCount == 3,
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
    await #expect(throws: TranscriptStoreError.sessionNotFound(missing)) {
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

    let listing = try await store.list()
    #expect(listing.sessions.map(\.id) == [good.id])
    // O diretório com `{não sou json` TEM um `session.json` — é uma sessão que
    // não dá para ler, não um diretório que não é sessão. Ver
    // `aSessionWithUnreadableMetadataIsReportedNotDroppedFromTheList`.
    #expect(listing.unreadable.count == 1)
}

@Test func listOnAnEmptyOrMissingRootIsEmptyNotAnError() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(try await FileTranscriptStore(root: root).list() == SessionListing())

    let missing = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("nao-existe-\(UUID().uuidString)")
    #expect(try await FileTranscriptStore(root: missing).list() == SessionListing())
}

/// O caso difícil do MF-1, e o que a Task 5 existe para impedir.
///
/// `kill -9` no meio de uma escrita não para em fronteira de caractere: ele
/// para no meio de um "ç" (0xC3 0xA7), e o arquivo fica com um 0xC3 solto.
/// Enquanto a leitura era `String(contentsOf:encoding:.utf8)`, a construção do
/// `String` falhava para o ARQUIVO INTEIRO e `entries(of:in:)` devolvia `[]` —
/// não uma entrada perdida, mas a sessão inteira, e PARA SEMPRE: o byte
/// inválido fica no arquivo, então toda entrada escrita depois do restart
/// também some. Medido antes da correção: 3 entradas boas mais esta cauda
/// davam `load().allEntries.count == 0`, `list().entryCount == 0`, e
/// `0` de novo depois de restart + append.
///
/// O transcript é cheio de não-ASCII — prosa do usuário, saída de ferramenta,
/// o português deste projeto — então o caso ruim não é exótico.
@Test func aTailCutInsideAMultiByteCharacterCostsOneEntryNotTheWholeSession() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let segment = Segment(harness: harnessA, harnessSessionID: UUID(), model: "m")
    let session = Session(title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
                          segments: [segment])
    try await store.saveMetadata(session)
    try await store.append(entry("um"), to: segment.id, in: session.id)
    try await store.append(entry("dois"), to: segment.id, in: session.id)
    try await store.append(entry("três"), to: segment.id, in: session.id)

    // A escrita morre DENTRO do "ç" de "correção": o último byte do arquivo é
    // 0xC3, a primeira metade de um caractere de dois bytes. O arquivo deixa
    // de ser UTF-8 válido — não numa linha, no arquivo.
    let file = root.appendingPathComponent(session.id.uuidString)
        .appendingPathComponent("\(segment.id.uuidString).ndjson")
    var fragment = Data(#"{"id":"11111111-1111-1111-1111-111111111111","kind":{"assistantText":{"_0":"corre"#.utf8)
    fragment.append(0xC3)
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: fragment)
    try handle.close()

    // Pré-condição do teste: o arquivo realmente não é mais UTF-8 válido —
    // é isso que separa este fixture do fácil, e é o finding inteiro.
    let asOneString = try? String(contentsOf: file, encoding: .utf8)
    #expect(asOneString == nil,
             "o fixture precisa cortar DENTRO do caractere, não numa fronteira")

    let afterCrash = try await store.load(session.id)
    #expect(texts(of: afterCrash) == ["um", "dois", "três"],
             "meio caractere não pode custar a conversa inteira")

    // E o dano não pode ser permanente: o byte inválido continua no arquivo,
    // então o app reiniciando e resumindo o mesmo segmento (spec §5.1) tem que
    // seguir lendo — o seu e o que escrever daqui para a frente.
    try await store.append(entry("quatro"), to: segment.id, in: session.id)
    let afterRestart = try await store.load(session.id)
    #expect(texts(of: afterRestart) == ["um", "dois", "três", "quatro"],
             "a entrada escrita depois do restart não pode ficar invisível")

    // `list()` conta linhas, e contava 0 pelo mesmo motivo.
    let listing = try await store.list()
    #expect(listing.sessions.first?.entryCount == 5,
             "quatro linhas boas mais a cauda cortada")
}

// MARK: - session.json: uma sessão danificada não pode sumir calada

/// Um `Handoff` de uma versão futura dentro do `session.json`.
///
/// Escrito exatamente como o Swift o emitiria para um terceiro caso —
/// `{"<nome>":{...}}`, o mesmo formato dos dois que existem. Antes da
/// correção isto derrubava a sessão inteira nas três operações de uma vez.
private let futureHandoffJSON = #"{"summarizeWithModel":{"model":"m-9","tokens":800}}"#

private func sessionJSONWithFutureHandoff(session: Session, segment: Segment) -> Data {
    Data(#"""
    {"id":"\#(session.id.uuidString)","segments":[{"entries":[],"harness":"harness-a","harnessSessionID":"\#(segment.harnessSessionID.uuidString)","id":"\#(segment.id.uuidString)","model":"m","seededBy":\#(futureHandoffJSON),"usage":{"cacheCreationTokens":0,"cacheReadTokens":0,"costUSD":0,"inputTokens":0,"outputTokens":0}}],"title":"t","workingDirectory":"file:///tmp"}
    """#.utf8)
}

@Test func aSessionSeededByAFutureHandoffStillLoadsListsAndAppends() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let segment = Segment(harness: harnessA, harnessSessionID: UUID(), model: "m")
    let session = Session(title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
                          segments: [segment])
    try await store.saveMetadata(session)
    // Uma versão futura regrava os metadados com uma estratégia de handoff que
    // este binário não conhece.
    try sessionJSONWithFutureHandoff(session: session, segment: segment)
        .write(to: root.appendingPathComponent(session.id.uuidString)
            .appendingPathComponent("session.json"))

    // 1. A sessão abre.
    let loaded = try await store.load(session.id)
    #expect(loaded.id == session.id)
    guard case .unrecognized(let discriminator, let payload) =
            loaded.segments.first?.seededBy else {
        Issue.record("esperava .unrecognized, achei \(String(describing: loaded.segments.first?.seededBy))")
        return
    }
    #expect(discriminator == "summarizeWithModel")
    #expect(payload["model"] == .string("m-9"))

    // 2. Ela não some da lista.
    let listing = try await store.list()
    #expect(listing.sessions.map(\.id) == [session.id])
    #expect(listing.unreadable.isEmpty)

    // 3. E dá para continuar escrevendo nela.
    try await store.append(entry("depois"), to: segment.id, in: session.id)
    #expect(texts(of: try await store.load(session.id)) == ["depois"])
}

@Test func reencodingAFutureHandoffKeepsItsOriginalNameNotTheWordUnrecognized() async throws {
    // Mesma exigência de idempotência do `Kind`: um binário velho que só abriu
    // e regravou os metadados (rename, compactação) não pode degradar a
    // proveniência permanentemente — inclusive para a versão nova, que entende
    // "summarizeWithModel" perfeitamente bem.
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let segment = Segment(harness: harnessA, harnessSessionID: UUID(), model: "m")
    let session = Session(title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
                          segments: [segment])
    try await store.saveMetadata(session)
    let metadata = root.appendingPathComponent(session.id.uuidString)
        .appendingPathComponent("session.json")
    try sessionJSONWithFutureHandoff(session: session, segment: segment).write(to: metadata)

    var renamed = try await store.load(session.id)
    renamed.title = "outro título"
    try await store.saveMetadata(renamed)

    let rewritten = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: metadata))
    let seededBy = rewritten["segments"]?.arrayValue?.first?["seededBy"]
    #expect(seededBy?["summarizeWithModel"]?["model"] == .string("m-9"))
    #expect(seededBy?["unrecognized"] == nil)
}

@Test func aSessionWithUnreadableMetadataIsReportedNotDroppedFromTheList() async throws {
    // O `try?` do `list()` foi escrito para "este diretório não é uma sessão"
    // e passou a engolir também "esta sessão eu não consigo ler". A conversa
    // do usuário sumia da interface sem diagnóstico nenhum. As duas coisas
    // agora se distinguem pelo arquivo de metadados: sem `session.json` ali
    // nunca houve sessão; com um `session.json` que não abre, há.
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let good = Session(title: "boa", workingDirectory: URL(fileURLWithPath: "/tmp"), segments: [])
    try await store.saveMetadata(good)

    // Uma sessão de verdade cujos metadados não abrem.
    let damagedID = UUID()
    let damaged = root.appendingPathComponent(damagedID.uuidString)
    try FileManager.default.createDirectory(at: damaged, withIntermediateDirectories: true)
    try Data(#"{"id":"não sou uma sessão válida"#.utf8)
        .write(to: damaged.appendingPathComponent("session.json"))

    // Um diretório que nunca foi sessão nenhuma.
    try FileManager.default.createDirectory(
        at: root.appendingPathComponent("nem-diretorio-de-sessao"),
        withIntermediateDirectories: true)

    let listing = try await store.list()
    #expect(listing.sessions.map(\.id) == [good.id],
             "a sessão boa continua listada — uma danificada não derruba a lista")
    #expect(listing.unreadable.count == 1,
             "a sessão danificada é relatada, não omitida")
    #expect(listing.unreadable.first?.id == damagedID)
    // Comparação por caminho resolvido: o diretório temporário do macOS é
    // `/var/...`, symlink para `/private/var/...`, e a enumeração devolve o
    // caminho resolvido e com barra final. O que se afirma aqui é que a URL
    // aponta para os MESMOS bytes, não que ela foi soletrada igual.
    #expect(listing.unreadable.first?.location.resolvingSymlinksInPath().path
            == damaged.resolvingSymlinksInPath().path)
    #expect(listing.unreadable.first?.reason.isEmpty == false)
}

// MARK: - updatedAt segue o transcript, não só os metadados

/// `updatedAt` era o mtime do `session.json`, e `append` escreve só no
/// `.ndjson`: medido, a variação depois de um append era 0,0 s. Uma sessão
/// conversada por uma hora reportava o horário do último rename.
///
/// Datas fixadas à mão em vez de lidas do relógio — a asserção é sobre QUAL
/// arquivo manda, não sobre quanto tempo passou.
@Test func updatedAtFollowsTheTranscriptAndNotOnlyTheMetadata() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let segment = Segment(harness: harnessA, harnessSessionID: UUID(), model: "m")
    let session = Session(title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
                          segments: [segment])
    try await store.saveMetadata(session)
    try await store.append(entry("um"), to: segment.id, in: session.id)

    let directory = root.appendingPathComponent(session.id.uuidString)
    let oldMetadata = Date(timeIntervalSince1970: 1_000_000_000) // 2001
    let recentAppend = Date(timeIntervalSince1970: 1_900_000_000) // 2030
    try FileManager.default.setAttributes(
        [.modificationDate: oldMetadata],
        ofItemAtPath: directory.appendingPathComponent("session.json").path)
    try FileManager.default.setAttributes(
        [.modificationDate: recentAppend],
        ofItemAtPath: directory.appendingPathComponent("\(segment.id.uuidString).ndjson").path)

    let listing = try await store.list()
    let updatedAt = try #require(listing.sessions.first?.updatedAt)
    #expect(abs(updatedAt.timeIntervalSince(recentAppend)) < 0.001,
             "updatedAt tem que vir do segmento, que é o arquivo que o append toca")
}

@Test func updatedAtStillComesFromTheMetadataWhenNoSegmentHasBeenWrittenYet() async throws {
    // Uma sessão recém-criada não tem `.ndjson` nenhum. O máximo de um
    // conjunto onde só existe o metadado é o metadado.
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let session = Session(title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
                          segments: [Segment(harness: harnessA, harnessSessionID: UUID(), model: "m")])
    try await store.saveMetadata(session)
    let created = Date(timeIntervalSince1970: 1_500_000_000)
    try FileManager.default.setAttributes(
        [.modificationDate: created],
        ofItemAtPath: root.appendingPathComponent(session.id.uuidString)
            .appendingPathComponent("session.json").path)

    let updatedAt = try #require(try await store.list().sessions.first?.updatedAt)
    #expect(abs(updatedAt.timeIntervalSince(created)) < 0.001)
}

@Test func listPutsTheMostRecentlyTouchedSessionFirst() async throws {
    // "Conversas mais recentes primeiro" é a primeira coisa que a lista de
    // sessões vai pedir deste store, e a ordem de enumeração do diretório não
    // dá isso — não dá ordem nenhuma.
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    var ids: [UUID] = []
    // Datas fora de ordem alfabética/criação de propósito: a do meio é a mais
    // recente, então nem "ordem de criação" nem "ordem de id" acertariam.
    for stamp in [1_200_000_000.0, 1_900_000_000.0, 1_500_000_000.0] {
        let session = Session(title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
                              segments: [])
        try await store.saveMetadata(session)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: stamp)],
            ofItemAtPath: root.appendingPathComponent(session.id.uuidString)
                .appendingPathComponent("session.json").path)
        ids.append(session.id)
    }

    let listed = try await store.list().sessions.map(\.id)
    #expect(listed == [ids[1], ids[2], ids[0]])
}
