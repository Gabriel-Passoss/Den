import Foundation

/// Um acontecimento que a UI consome enquanto ele acontece.
///
/// Efêmero de propósito (spec §4.4): `--include-partial-messages` emite deltas
/// de token, e se cada delta virasse uma entrada um turno viraria centenas de
/// entradas no store. Este tipo vai para o cockpit delta a delta e morre ali;
/// o que sobrevive é a `TranscriptEntry`, que nasce consolidada quando o turno
/// fecha.
///
/// **Não conforma a `Codable`, e isso é deliberado.** Conformar convidaria a
/// persistir — e persistir este fluxo ao lado do durável é exatamente a
/// duplicação que a §4.4 existe para impedir. Se um dia algo aqui precisar
/// sobreviver a um reinício, o lugar dele é uma `TranscriptEntry`.
public enum SessionEvent: Sendable, Equatable {
    /// O harness subiu e disse com que modelo, e em que sessão dele.
    ///
    /// O `harnessSessionID` vem como `String` porque é a grafia do harness, não
    /// a nossa: quem compara com o `Segment.harnessSessionID` que nós geramos é
    /// a camada de sessão, e uma divergência ali significa que o resume não
    /// pegou a sessão que pedimos.
    case sessionInitialized(model: String, harnessSessionID: String)
    /// Um turno começou. O cockpit limpa os rascunhos de bloco.
    case turnStarted
    /// Um pedaço de texto do assistente.
    case textDelta(blockIndex: Int, text: String)
    /// Um pedaço do raciocínio do assistente.
    case thinkingDelta(blockIndex: Int, text: String)
    /// Um pedaço do input de uma ferramenta, como JSON ainda incompleto.
    ///
    /// Chega em fatias que sozinhas não são JSON válido — é material de
    /// exibição ("montando a chamada…"), não de análise. O input completo chega
    /// na entrada `.toolCall` quando o bloco fecha.
    case toolInputDelta(blockIndex: Int, partialJSON: String)
    /// Progresso que o harness relata e que não é semântica da conversa.
    case notice(subtype: String, text: String)
}

/// O que sai do mapeador ao consumir uma linha do harness.
///
/// Os dois fluxos da spec §4.4, separados no tipo em vez de num único canal
/// que o chamador filtra: `events` vai para o cockpit, `entries` vai para o
/// `Segment`. Uma linha pode produzir nenhum, um ou vários de cada.
public struct MappedOutput: Sendable, Equatable {
    /// Efêmero — para a UI.
    public var events: [SessionEvent]
    /// Durável — para o transcript.
    public var entries: [TranscriptEntry]

    public init(events: [SessionEvent] = [], entries: [TranscriptEntry] = []) {
        self.events = events
        self.entries = entries
    }

    public static let empty = MappedOutput()
}
