import Foundation
import Darwin

/// Um diretório por sessão: `session.json` com os metadados e um NDJSON
/// append-only por segmento.
///
/// Zero dependências, legível com `cat` quando algo der errado, e natural para
/// um log append-only (spec §4.3).
public actor FileTranscriptStore: TranscriptStore {
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
        // segmentos que o `session.json` lista. `TranscriptStoreError.segmentNotFound`
        // existe exatamente para fechar esse buraco, e a precondição está
        // escrita na doc do protocolo — é contrato, não detalhe desta
        // implementação.
        let metadata = metadataFile(for: sessionID)
        guard FileManager.default.fileExists(atPath: metadata.path) else {
            throw TranscriptStoreError.sessionNotFound(sessionID)
        }
        let session = try decoder.decode(Session.self, from: Data(contentsOf: metadata))
        guard session.segments.contains(where: { $0.id == segmentID }) else {
            throw TranscriptStoreError.segmentNotFound(segmentID)
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
        // decodifica por linha, então o fragmento e a entrada nova virariam
        // UMA linha só, ilegível: a entrada nova, completa e íntegra, seria
        // perdida junto com o fragmento que já estava perdido por direito. A
        // garantia deste tipo — "uma linha truncada custa uma entrada, não a
        // sessão" — só vale de fato se a próxima escrita não puder contaminar
        // a que veio antes dela.
        //
        // `fstat` + `pread` no descritor já aberto (não um `stat`/leitura
        // via `FileManager` separados) para não abrir o arquivo duas vezes;
        // `pread` não mexe no offset de leitura/escrita do descritor, então
        // não interfere com o `O_APPEND` da escrita logo abaixo.
        //
        // Isso tem uma janela de corrida entre duas INSTÂNCIAS concorrentes
        // (o `pread` e o `write` não são atômicos juntos), mas o pior caso é
        // benigno: uma linha em branco a mais, que `entries(of:in:)` já
        // descarta. O caso que esta guarda existe para fechar — um processo
        // reiniciando sozinho e resumindo seu próprio segmento — não tem
        // escritor concorrente, então não tem essa corrida.
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
            throw TranscriptStoreError.sessionNotFound(sessionID)
        }
        var session = try decoder.decode(Session.self, from: Data(contentsOf: metadata))
        session.segments = session.segments.map { segment in
            var filled = segment
            filled.entries = entries(of: segment.id, in: sessionID)
            return filled
        }
        return session
    }

    /// Lista as sessões sem carregar o transcript de nenhuma delas, mais
    /// recentes primeiro.
    ///
    /// Um diretório SEM `session.json` não é uma sessão e não vira nada: nunca
    /// houve conversa ali. Um diretório COM `session.json` que não abre é
    /// outra coisa inteiramente — existe uma conversa do usuário ali — e vai
    /// para `SessionListing.unreadable`, com id, caminho e motivo. O `try?`
    /// único que cobria os dois casos foi escrito para o primeiro e passou a
    /// engolir o segundo em silêncio.
    ///
    /// - Important: `SessionSummary.entryCount` conta LINHAS em disco, não
    ///   entradas decodificadas — ver a nota em `lineCount(of:)`. Sobre um
    ///   segmento com uma linha danificada, este número pode vir MAIOR que
    ///   `load(_:).allEntries.count` para a mesma sessão. Não é um bug: são
    ///   duas perguntas diferentes ("quantas linhas o arquivo tem" vs.
    ///   "quantas entradas dessas eu consigo de fato ler de volta") que só
    ///   coincidem quando o arquivo está inteiro.
    public func list() throws -> SessionListing {
        let manager = FileManager.default
        // Sem `includingPropertiesForKeys`: o único prefetch que fazia sentido
        // aqui seria de uma propriedade lida DESTAS URLs, e as datas de que
        // `list()` precisa vêm do `session.json` e dos `.ndjson` lá dentro —
        // URLs construídas depois, que não herdam cache nenhum. Pedir a chave
        // nas URLs de diretório era trabalho cujo resultado nunca era
        // consultado.
        guard let directories = try? manager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil) else {
            return SessionListing()
        }

        var sessions: [SessionSummary] = []
        var unreadable: [UnreadableSession] = []
        for directory in directories {
            let metadata = directory.appendingPathComponent("session.json")
            guard manager.fileExists(atPath: metadata.path) else { continue }
            do {
                let session = try decoder.decode(
                    Session.self, from: Data(contentsOf: metadata))
                // O metadado guarda segmentos SEM entradas, então
                // `SessionSummary(session:)` contaria zero. A contagem vem das
                // linhas dos NDJSON — barata, sem decodificar nada. Ver a nota
                // de divergência com `load()` na doc de `lineCount(of:)`.
                var count = 0
                // `updatedAt` é o mtime mais recente entre os metadados e os
                // arquivos de segmento, e não só o dos metadados: `append`
                // escreve APENAS no `.ndjson`, então um `updatedAt` tirado do
                // `session.json` não se move quando a conversa se move —
                // medido, a variação depois de um append era 0,0 s, e uma
                // sessão conversada por uma hora reportava o horário do último
                // rename. É um `stat` por segmento, sem ler conteúdo nenhum.
                var updated = modificationDate(of: metadata) ?? .distantPast
                for segment in session.segments {
                    let file = segmentFile(segment.id, in: session.id)
                    count += lineCount(of: file)
                    if let touched = modificationDate(of: file), touched > updated {
                        updated = touched
                    }
                }
                sessions.append(SessionSummary(
                    id: session.id, title: session.title,
                    workingDirectory: session.workingDirectory,
                    harnesses: session.segments.map(\.harness),
                    usage: session.totalUsage, entryCount: count, updatedAt: updated))
            } catch {
                unreadable.append(UnreadableSession(
                    id: UUID(uuidString: directory.lastPathComponent),
                    location: directory,
                    reason: String(describing: error)))
            }
        }

        // Mais recentes primeiro — a primeira coisa que a lista de conversas
        // vai pedir deste store, e que a ordem de enumeração do diretório não
        // dá. Desempate por id para a ordem ser total e estável: sem ele, duas
        // sessões com o mesmo mtime sairiam em ordem arbitrária do sistema de
        // arquivos, e a lista dançaria entre dois refreshes.
        sessions.sort {
            $0.updatedAt == $1.updatedAt
                ? $0.id.uuidString < $1.id.uuidString
                : $0.updatedAt > $1.updatedAt
        }
        unreadable.sort { $0.location.path < $1.location.path }
        return SessionListing(sessions: sessions, unreadable: unreadable)
    }

    /// O mtime de um arquivo, ou `nil` se ele não existe.
    ///
    /// `stat` direto em vez de `URL.resourceValues`: é a informação exata que
    /// se quer, um syscall, sem construir dicionário nenhum — e `list()` faz
    /// isso uma vez por segmento de cada sessão.
    private func modificationDate(of file: URL) -> Date? {
        var status = stat()
        guard stat(file.path, &status) == 0 else { return nil }
        return Date(timeIntervalSince1970: Double(status.st_mtimespec.tv_sec)
            + Double(status.st_mtimespec.tv_nsec) / 1_000_000_000)
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
    /// - Important: a leitura é de BYTES, e o corte de linhas é em `0x0A` —
    ///   nunca `String(contentsOf:encoding:.utf8)`. Um processo morto no meio
    ///   de uma escrita não para em fronteira de caractere: ele para no meio
    ///   de um "ç", e o arquivo inteiro deixa de ser UTF-8 válido. A
    ///   construção do `String` falhava para o ARQUIVO todo, esta função
    ///   devolvia `[]`, e a sessão inteira desaparecia — não uma entrada, mas
    ///   todas, PARA SEMPRE: o byte inválido fica no arquivo, então toda
    ///   entrada escrita depois do restart também ficava invisível. Medido:
    ///   3 entradas boas mais uma cauda cortada dentro de um "ç" davam 0. No
    ///   nível de byte, o dano fica contido na linha danificada — os bytes
    ///   inválidos fazem o JSON daquela linha falhar, e só dela.
    ///
    /// Isso não é o mesmo buraco que `TranscriptEntry.Kind.unrecognized`
    /// fecha. Um discriminador que esta versão não conhece, mas escrito por
    /// uma versão futura, decodifica normalmente — vira `.unrecognized`, não
    /// um erro. Uma linha que chega até aqui e AINDA falha ao decodificar não
    /// é um caso futuro chegando cedo demais: é JSON de verdade quebrado
    /// (truncado, sobrescrito, editado à mão) — ou, e isto é uma lacuna
    /// conhecida e registrada nas pendências, o PAYLOAD de um discriminador
    /// conhecido numa forma futura.
    ///
    /// - Note: a entrada ilegível é perdida, não recuperada. Se o transcript
    ///   precisar um dia ser à prova de perda, o caminho é escrever tamanho +
    ///   linha, não tentar reparar JSON. Esse mesmo dia faria
    ///   `lineCount(of:)` e esta função voltarem a concordar (ver a nota
    ///   de divergência lá).
    ///
    /// - Note: `.mappedIfSafe` evita copiar o arquivo inteiro para a heap. O
    ///   risco conhecido do mapeamento é `SIGBUS` se alguém TRUNCAR o arquivo
    ///   enquanto ele está mapeado; este é um log append-only, e nada neste
    ///   tipo encurta um segmento — o único jeito de chegar lá é uma mão de
    ///   fora mexendo no diretório durante a leitura.
    private func entries(of segmentID: UUID, in sessionID: UUID) -> [TranscriptEntry] {
        let file = segmentFile(segmentID, in: sessionID)
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return [] }
        return data.split(separator: 0x0A, omittingEmptySubsequences: true)
            .compactMap { try? decoder.decode(TranscriptEntry.self, from: Data($0)) }
    }

    /// Conta linhas não vazias em disco — barato de propósito, para servir
    /// `list()` sem decodificar um NDJSON inteiro por sessão só para contar.
    ///
    /// - Important: conta BYTES, mapeando o arquivo. A versão anterior
    ///   construía um `String` do arquivo inteiro, e isso custava o tamanho do
    ///   transcript em cada listagem: medido em release, cache quente, 12
    ///   sessões de 1500 entradas e 22 MiB, `list()` levava 267–293 ms — 80%
    ///   do custo de carregar UMA sessão inteira, a inversão exata que a
    ///   separação `session.json`/NDJSON existe para evitar. Pior, era um
    ///   `list()` lento por VOLUME DE TRANSCRIPT, e a §4.3 usa "listar ficou
    ///   lento" como o gatilho para migrar ao SQLite — o gatilho dispararia
    ///   por um artefato deste código. Herda de quebra a correção de UTF-8 de
    ///   `entries(of:in:)`: um arquivo com um byte inválido contava 0 aqui.
    ///
    /// - Important: **Diverge de propósito de `entries(of:in:).count`.** Esta
    ///   função conta LINHAS: uma linha truncada (a última escrita de um
    ///   processo morto no meio) ou uma linha corrompida no meio do arquivo
    ///   ainda soma 1 aqui — ela existe nos bytes, mesmo sem decodificar.
    ///   `entries(of:in:)` conta o oposto: só o que passou por `JSONDecoder`
    ///   com sucesso. Sobre um segmento com uma linha danificada, o
    ///   `entryCount` de `list()` (que soma este número) fica MAIOR que
    ///   `load(_:).allEntries.count` para a mesma sessão — mesmos bytes, duas
    ///   perguntas diferentes ("quantas linhas existem" vs. "quantas eu
    ///   consigo ler de volta").
    ///   `listCountsRawLinesWhileLoadCountsDecodableEntries` em
    ///   `FileTranscriptStoreResilienceTests.swift` fixa esse número para que
    ///   a divergência não vire uma surpresa silenciosa se um dos dois lados
    ///   mudar de comportamento no futuro. Fechar essa lacuna do jeito certo —
    ///   fazer os dois concordarem sempre — pede o mesmo write-side fix já
    ///   anotado em `entries(of:in:)`: tamanho + linha em vez de JSON solto,
    ///   para que "quantas linhas existem" pare de poder incluir uma que não é
    ///   de fato uma linha.
    private func lineCount(of file: URL) -> Int {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return 0 }
        return data.withUnsafeBytes { buffer -> Int in
            var count = 0
            var openLine = false
            for byte in buffer {
                if byte == 0x0A {
                    if openLine { count += 1; openLine = false }
                } else {
                    openLine = true
                }
            }
            // A última linha conta mesmo sem `\n` final — ver a nota de
            // divergência acima.
            return openLine ? count + 1 : count
        }
    }
}
