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
        let fd = open(file.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard fd != -1 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(fd) }
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
        session.segments = try session.segments.map { segment in
            var filled = segment
            filled.entries = try entries(of: segment.id, in: sessionID)
            return filled
        }
        return session
    }

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
            // linhas dos NDJSON — barata, sem decodificar nada.
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

    private func entries(of segmentID: UUID, in sessionID: UUID) throws -> [TranscriptEntry] {
        let file = segmentFile(segmentID, in: sessionID)
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return try text.split(separator: "\n")
            .filter { !$0.isEmpty }
            .map { try decoder.decode(TranscriptEntry.self, from: Data($0.utf8)) }
    }

    private func lineCount(of segmentID: UUID, in sessionID: UUID) -> Int {
        guard let text = try? String(contentsOf: segmentFile(segmentID, in: sessionID),
                                     encoding: .utf8) else { return 0 }
        return text.split(separator: "\n").filter { !$0.isEmpty }.count
    }
}
