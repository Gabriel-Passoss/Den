import Foundation
import Darwin

/// Um diretório por sessão: `session.json` com os metadados e um NDJSON
/// append-only por segmento.
///
/// Zero dependências, legível com `cat` quando algo der errado, e natural para
/// um log append-only (spec §4.3).
public actor FileTranscriptStore: TranscriptStore {
    public enum StoreError: Error, Equatable {
        case sessionNotFound(UUID)
        case segmentNotFound(UUID)
    }

    private let root: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL) {
        self.root = root
        let encoder = JSONEncoder()
        // O formato em disco é o CONTRATO deste tipo, não um detalhe de
        // implementação: datas são ISO-8601 no disco, e uma implementação
        // futura em SQLite precisa continuar lendo o que esta escreveu. Nada
        // no próprio `TranscriptEntry` impõe uma estratégia de codificação —
        // ficaria a critério de cada call site, e dois componentes escolhendo
        // estratégias diferentes discordariam silenciosamente na hora de ler
        // o que o outro escreveu. Fixar a estratégia aqui, no único lugar que
        // grava e lê o disco, é o que evita essa armadilha.
        encoder.dateEncodingStrategy = .iso8601
        // Uma entrada por linha: nada de pretty-printing no NDJSON.
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    private func directory(for sessionID: UUID) -> URL {
        root.appendingPathComponent(sessionID.uuidString)
    }

    private func metadataFile(for sessionID: UUID) -> URL {
        directory(for: sessionID).appendingPathComponent("session.json")
    }

    private func segmentFile(_ segmentID: UUID, in sessionID: UUID) -> URL {
        directory(for: sessionID).appendingPathComponent("\(segmentID.uuidString).ndjson")
    }

    public func saveMetadata(_ session: Session) throws {
        try FileManager.default.createDirectory(
            at: directory(for: session.id), withIntermediateDirectories: true)
        // As entradas moram nos NDJSON; os metadados guardam os segmentos vazios.
        var stripped = session
        stripped.segments = session.segments.map {
            var segment = $0
            segment.entries = []
            return segment
        }
        try encoder.encode(stripped).write(to: metadataFile(for: session.id), options: .atomic)
    }

    public func append(_ entry: TranscriptEntry, to segmentID: Segment.ID,
                       in sessionID: Session.ID) throws {
        // Valida contra os metadados persistidos ANTES de escrever: sem
        // isso, um `segmentID`/`sessionID` que nunca esteve no
        // `session.json` (bug de ordenação a montante, segmento removido dos
        // metadados) escreve silenciosamente num arquivo que `load()` e
        // `list()` nunca vão enumerar, porque os dois só andam pelos
        // segmentos que o `session.json` lista. `StoreError.segmentNotFound`
        // existe exatamente para fechar esse buraco.
        let metadata = metadataFile(for: sessionID)
        guard FileManager.default.fileExists(atPath: metadata.path) else {
            throw StoreError.sessionNotFound(sessionID)
        }
        let session = try decoder.decode(Session.self, from: Data(contentsOf: metadata))
        guard session.segments.contains(where: { $0.id == segmentID }) else {
            throw StoreError.segmentNotFound(segmentID)
        }

        var line = try encoder.encode(entry)
        line.append(0x0A)

        // Uma única rota, aberta com O_APPEND — não duas (fileExists ? write
        // atômico baseado em rename : seekToEnd + write). O actor só
        // serializa chamadas DENTRO de uma instância; duas instâncias sobre
        // o MESMO root (duas janelas do DevSpace, ou uma janela e a sonda de
        // diagnóstico) só compartilham o arquivo, não o isolamento do actor.
        // As duas rotas antigas tinham corrida entre instâncias: a primeira
        // escrita (ambas veem !fileExists, ambas fazem o write atômico —
        // quem renomeia por último vence, a outra entrada some sem erro) e
        // toda escrita seguinte (seek e write são dois passos — duas
        // instâncias podem calcular o mesmo offset de fim-de-arquivo antes
        // de qualquer uma escrever, e a segunda pisa em cima da primeira).
        // `O_APPEND` empurra o seek-até-o-fim para dentro do próprio kernel,
        // que o faz atomicamente em relação a outros escritores do mesmo
        // arquivo — fechando as duas corridas de uma vez. E não precisa mais
        // decidir entre duas rotas, então o código fica menor, não maior.
        //
        // A garantia é do sistema de arquivos, não da linguagem: vale para
        // filesystems locais (APFS, ext4, ...). Nem todo filesystem de rede
        // honra `O_APPEND` atomicamente entre escritores — um `root` num
        // compartilhamento de rede está trocando essa garantia fora.
        let file = segmentFile(segmentID, in: sessionID)
        // O_RDWR, não O_WRONLY: a guarda de newline abaixo precisa ler o
        // último byte do arquivo pelo MESMO descritor antes de escrever.
        let fd = open(file.path, O_RDWR | O_CREAT | O_APPEND, 0o644)
        guard fd != -1 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(fd) }

        // Guarda de newline: se o processo morreu no meio de uma escrita
        // anterior, a última linha do arquivo ficou sem `\n` final. Sem essa
        // guarda, o próximo `append` — depois de um restart que resume o
        // MESMO segmento (spec §5.1: idle → hot é `--resume` da mesma
        // harness session, então o mesmo arquivo é reaberto) — escreveria os
        // bytes novos GRUDADOS no fragmento truncado. `entries(of:in:)`
        // decodifica por linha (`split(separator: "\n")`), então o
        // fragmento e a entrada nova virariam UMA linha só, ilegível: a
        // entrada nova, completa e íntegra, seria perdida junto com o
        // fragmento que já estava perdido por direito. A garantia deste
        // tipo — "uma linha truncada custa uma entrada, não a sessão" — só
        // vale de fato se a próxima escrita não puder contaminar a que veio
        // antes dela.
        //
        // `fstat` + `pread` no descritor já aberto (não um `stat`/leitura
        // via `FileManager` separados) para não abrir o arquivo duas vezes;
        // `pread` não mexe no offset de leitura/escrita do descritor, então
        // não interfere com o `O_APPEND` da escrita logo abaixo.
        //
        // Isso tem uma janela de corrida entre duas INSTÂNCIAS concorrentes
        // (o `pread` e o `write` não são atômicos juntos), mas o pior caso é
        // benigno: uma linha em branco a mais, que `entries(of:in:)` já
        // filtra (`.filter { !$0.isEmpty }`). O caso que esta guarda existe
        // para fechar — um processo reiniciando sozinho e resumindo seu
        // próprio segmento — não tem escritor concorrente, então não tem
        // essa corrida.
        var status = stat()
        guard fstat(fd, &status) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        if status.st_size > 0 {
            var lastByte: UInt8 = 0
            let bytesRead = withUnsafeMutableBytes(of: &lastByte) { buffer in
                pread(fd, buffer.baseAddress, 1, status.st_size - 1)
            }
            guard bytesRead >= 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if bytesRead == 1 && lastByte != 0x0A {
                line.insert(0x0A, at: line.startIndex)
            }
        }

        try line.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard var pointer = buffer.baseAddress else { return }
            var remaining = buffer.count
            while remaining > 0 {
                let written = write(fd, pointer, remaining)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                pointer = pointer.advanced(by: written)
                remaining -= written
            }
        }
    }

    public func load(_ sessionID: Session.ID) throws -> Session {
        let metadata = metadataFile(for: sessionID)
        guard FileManager.default.fileExists(atPath: metadata.path) else {
            throw StoreError.sessionNotFound(sessionID)
        }
        var session = try decoder.decode(Session.self, from: Data(contentsOf: metadata))
        session.segments = session.segments.map { segment in
            var filled = segment
            filled.entries = entries(of: segment.id, in: sessionID)
            return filled
        }
        return session
    }

    /// Lista as sessões sem carregar o transcript de nenhuma delas.
    ///
    /// - Important: `SessionSummary.entryCount` conta LINHAS em disco, não
    ///   entradas decodificadas — ver a nota em `lineCount(of:in:)`. Sobre um
    ///   segmento com uma linha danificada, este número pode vir MAIOR que
    ///   `load(_:).allEntries.count` para a mesma sessão. Não é um bug: são
    ///   duas perguntas diferentes ("quantas linhas o arquivo tem" vs.
    ///   "quantas entradas dessas eu consigo de fato ler de volta") que só
    ///   coincidem quando o arquivo está inteiro.
    public func list() throws -> [SessionSummary] {
        let manager = FileManager.default
        guard let directories = try? manager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        return directories.compactMap { directory in
            let metadata = directory.appendingPathComponent("session.json")
            guard let data = try? Data(contentsOf: metadata),
                  let session = try? decoder.decode(Session.self, from: data)
            else { return nil }
            let modified = (try? metadata.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? Date(timeIntervalSince1970: 0)
            // O metadado guarda segmentos SEM entradas, então
            // `SessionSummary(session:)` contaria zero. A contagem vem das
            // linhas dos NDJSON — barata, sem decodificar nada. Ver a nota
            // de divergência com `load()` na doc de `lineCount(of:in:)`.
            let count = session.segments.reduce(0) { total, segment in
                total + lineCount(of: segment.id, in: session.id)
            }
            return SessionSummary(
                id: session.id, title: session.title,
                workingDirectory: session.workingDirectory,
                harnesses: session.segments.map(\.harness),
                usage: session.totalUsage, entryCount: count, updatedAt: modified)
        }
    }

    /// Lê as entradas de um segmento, pulando linhas ilegíveis.
    ///
    /// Um NDJSON append-only é escrito com o app rodando: se o processo morrer
    /// no meio de uma escrita, a última linha fica pela metade. Falhar a
    /// leitura inteira perderia a conversa por causa de meia linha — e é
    /// justamente quando o usuário mais quer o histórico de volta. Mesma regra
    /// da spec §5.4: degradar, não falhar.
    ///
    /// A tolerância não é só para a última linha. Uma linha corrompida no
    /// MEIO do arquivo (disco, edição manual, um segundo processo pisando no
    /// arquivo) é o mesmo problema visto de outro ângulo: uma entrada
    /// ilegível não pode esconder as entradas depois dela.
    ///
    /// Isso não é o mesmo buraco que `TranscriptEntry.Kind.unrecognized`
    /// fecha. Um discriminador que esta versão não conhece, mas escrito por
    /// uma versão futura, decodifica normalmente — vira `.unrecognized`, não
    /// um erro. Uma linha que chega até aqui e AINDA falha ao decodificar não
    /// é um caso futuro chegando cedo demais: é JSON de verdade quebrado
    /// (truncado, sobrescrito, editado à mão). Perder essa entrada é o preço
    /// de não perder as outras.
    ///
    /// - Note: a entrada ilegível é perdida, não recuperada. Se o transcript
    ///   precisar um dia ser à prova de perda, o caminho é escrever tamanho +
    ///   linha, não tentar reparar JSON. Esse mesmo dia faria
    ///   `lineCount(of:in:)` e esta função voltarem a concordar (ver a nota
    ///   de divergência lá).
    private func entries(of segmentID: UUID, in sessionID: UUID) -> [TranscriptEntry] {
        let file = segmentFile(segmentID, in: sessionID)
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return text.split(separator: "\n")
            .filter { !$0.isEmpty }
            .compactMap { try? decoder.decode(TranscriptEntry.self, from: Data($0.utf8)) }
    }

    /// Conta linhas não vazias em disco — barato de propósito, para servir
    /// `list()` sem decodificar um NDJSON inteiro por sessão só para contar.
    ///
    /// - Important: **Diverge de propósito de `entries(of:in:).count`.** Esta
    ///   função conta LINHAS: `split(separator: "\n")` inclui a última
    ///   subsequência mesmo sem `\n` final, então uma linha truncada (a
    ///   última escrita de um processo morto no meio) ou uma linha corrompida
    ///   no meio do arquivo ainda soma 1 aqui — ela existe nos bytes, mesmo
    ///   sem decodificar. `entries(of:in:)` conta o oposto: só o que passou
    ///   por `JSONDecoder` com sucesso. Sobre um segmento com uma linha
    ///   danificada, `list()`'s `entryCount` (que soma este número) fica
    ///   MAIOR que `load(_:).allEntries.count` para a mesma sessão — mesmos
    ///   bytes, duas perguntas diferentes ("quantas linhas existem" vs.
    ///   "quantas eu consigo ler de volta"). `listCountsRawLinesWhileLoadCountsDecodableEntries`
    ///   em `FileTranscriptStoreResilienceTests.swift` fixa esse número para
    ///   que a divergência não vire uma surpresa silenciosa se um dos dois
    ///   lados mudar de comportamento no futuro. Fechar essa lacuna do jeito
    ///   certo — fazer os dois concordarem sempre — pede o mesmo write-side
    ///   fix já anotado em `entries(of:in:)`: tamanho + linha em vez de JSON
    ///   solto, para que "quantas linhas existem" pare de poder incluir uma
    ///   que não é de fato uma linha.
    private func lineCount(of segmentID: UUID, in sessionID: UUID) -> Int {
        guard let text = try? String(contentsOf: segmentFile(segmentID, in: sessionID),
                                     encoding: .utf8) else { return 0 }
        return text.split(separator: "\n").filter { !$0.isEmpty }.count
    }
}
