import Foundation

/// As falhas que QUALQUER `TranscriptStore` pode ter, independentemente de
/// onde ele guarda os bytes.
///
/// Mora no protocolo, e não na implementação, porque um chamador que precisa
/// distinguir "essa sessão não existe" de "o disco está em chamas" só
/// consegue fazer isso nomeando o tipo do erro — e enquanto esse tipo era
/// `FileTranscriptStore.StoreError`, todo `catch` do app ficava amarrado à
/// implementação em arquivo. Trocar para SQLite quebraria cada um desses
/// sítios de chamada, o que faz da própria costura da §4.3 ("o SQLite entra
/// sem que nada acima perceba") letra morta.
///
/// Os dois casos são de domínio, não de meio: um id que não está lá é um id
/// que não está lá, em NDJSON ou em tabela. Falhas de meio — I/O, permissão,
/// JSON corrompido — continuam subindo como o erro nativo do meio, porque
/// achatá-las aqui perderia o diagnóstico sem ganhar portabilidade nenhuma.
public enum TranscriptStoreError: Error, Equatable {
    case sessionNotFound(UUID)
    case segmentNotFound(UUID)
}

/// O resultado de `list()`: as sessões que dá para resumir, e as que existem
/// mas este binário não consegue ler.
///
/// São duas coisas, e não uma, porque um `SessionSummary` de uma sessão
/// ilegível seria um objeto inventado: título, diretório e custo teriam que
/// sair de algum lugar, e o único lugar é o arquivo que não abriu. A
/// alternativa — deixar a sessão ilegível fora do array e pronto — é o
/// comportamento que o review mediu e chamou de perda silenciosa: a conversa
/// do usuário some da interface sem diagnóstico nenhum.
///
/// O tipo obriga o chamador a nomear `.sessions` para chegar na lista, então
/// ele VÊ o outro campo. Uma segunda função (`unreadableSessions()`) ou um
/// canal de diagnóstico lateral podem simplesmente nunca ser chamados — e uma
/// segunda função ainda varreria o diretório uma segunda vez, com uma janela
/// de corrida entre as duas varreduras.
public struct SessionListing: Sendable, Equatable {
    /// As sessões cujos metadados foram lidos. Mais recentes primeiro.
    public var sessions: [SessionSummary]
    /// As sessões que existem em disco e não puderam ser lidas.
    public var unreadable: [UnreadableSession]

    public init(sessions: [SessionSummary] = [], unreadable: [UnreadableSession] = []) {
        self.sessions = sessions
        self.unreadable = unreadable
    }
}

/// Uma sessão que existe e que este binário não consegue ler.
///
/// Não é o mesmo que "este diretório não é uma sessão". A diferença está no
/// arquivo de metadados: se ele não existe, ali nunca houve sessão nenhuma e
/// não há nada a relatar; se ele existe e não abre, existe uma conversa do
/// usuário ali e o silêncio seria a resposta errada.
public struct UnreadableSession: Sendable, Equatable {
    /// O id da sessão, quando o layout em disco permite deduzi-lo do nome do
    /// diretório. `nil` quando nem isso dá para afirmar.
    public let id: UUID?
    /// Onde ela está — o que o usuário precisa para chegar nos bytes com
    /// `cat`, que é meio ponto do formato em arquivo (spec §4.3).
    public let location: URL
    /// O que falhou, em texto. String e não `any Error` para o tipo continuar
    /// `Sendable` e `Equatable`; o diagnóstico é para ser LIDO, não capturado.
    public let reason: String

    public init(id: UUID?, location: URL, reason: String) {
        self.id = id
        self.location = location
        self.reason = reason
    }
}

/// Onde o transcript vive.
///
/// É a costura da spec §4.3: a primeira implementação é NDJSON em disco, e
/// quando listar ficar lento ou houver busca por conteúdo, o SQLite entra sem
/// que nada acima perceba.
public protocol TranscriptStore: Sendable {
    /// Grava os metadados da sessão — título, diretório e os segmentos SEM as
    /// entradas. Idempotente: chamar de novo não perturba o transcript.
    func saveMetadata(_ session: Session) async throws

    /// Acrescenta uma entrada ao fim do segmento.
    ///
    /// - Precondition: a sessão precisa ter metadados gravados, e o segmento
    ///   precisa estar listado neles. Senão lança
    ///   `TranscriptStoreError.sessionNotFound` ou `.segmentNotFound`, NUNCA
    ///   escrevendo a entrada. Isto é contrato do protocolo, não detalhe da
    ///   implementação em arquivo: sem ele, um id de segmento que nunca esteve
    ///   nos metadados (bug de ordenação a montante, segmento removido) grava
    ///   silenciosamente num lugar que `load()` e `list()` nunca vão
    ///   enumerar — a entrada existe em disco e não existe para o usuário. Uma
    ///   implementação em SQLite que não replique a validação muda esse
    ///   comportamento sem que nada acuse.
    ///
    /// - Note: a spec §4.3 escreve esta assinatura sem `sessionID`. O layout é
    ///   um diretório por sessão, e um id de segmento sozinho não diz em qual
    ///   sessão ele está — a alternativa seria manter um índice sincronizado
    ///   para poupar um parâmetro.
    func append(_ entry: TranscriptEntry, to segmentID: Segment.ID,
                in sessionID: Session.ID) async throws

    /// A sessão inteira, com o transcript.
    ///
    /// - Throws: `TranscriptStoreError.sessionNotFound` quando o id não
    ///   existe.
    func load(_ sessionID: Session.ID) async throws -> Session

    /// Uma linha por sessão, sem carregar transcript nenhum. Mais recentes
    /// primeiro.
    ///
    /// - Note: a spec §4.3 escreve o retorno como `[SessionSummary]`. Um array
    ///   só não tem onde dizer "existe uma sessão aqui que eu não consigo
    ///   ler", e a resposta anterior a isso era omiti-la — perda silenciosa.
    ///   Ver `SessionListing`. Mesma licença já usada em `append`, pelo mesmo
    ///   motivo: a §4.3 é um esboço de assinatura, e o comportamento errado
    ///   que ela deixaria passar é mais caro que a fidelidade literal.
    func list() async throws -> SessionListing
}
