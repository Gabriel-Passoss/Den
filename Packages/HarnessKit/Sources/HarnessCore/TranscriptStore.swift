import Foundation

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
    /// - Note: a spec §4.3 escreve esta assinatura sem `sessionID`. O layout é
    ///   um diretório por sessão, e um id de segmento sozinho não diz em qual
    ///   sessão ele está — a alternativa seria manter um índice sincronizado
    ///   para poupar um parâmetro.
    func append(_ entry: TranscriptEntry, to segmentID: Segment.ID,
                in sessionID: Session.ID) async throws

    /// A sessão inteira, com o transcript.
    func load(_ sessionID: Session.ID) async throws -> Session

    /// Uma linha por sessão, sem carregar transcript nenhum.
    func list() async throws -> [SessionSummary]
}
