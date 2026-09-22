import Foundation

public enum CompactionPhase: Sendable, Equatable {
    case started
    case finished
    case failed(reason: String)
}

public enum SessionEvent: Sendable, Equatable {

    case sessionInitialized(model: String, harnessSessionID: String,
                            catalog: CommandCatalog = .empty)

    case turnStarted

    case textDelta(blockIndex: Int, text: String)

    case thinkingDelta(blockIndex: Int, text: String)

    case toolInputDelta(blockIndex: Int, partialJSON: String)

    case notice(subtype: String, text: String)

    /// Quanto do contexto o modelo leu na última mensagem: é o número que
    /// sobe durante o turno e desaba quando a conversa é compactada.
    case contextUsage(tokens: Int)

    /// Nem todo harness entrega o catálogo no init: alguns anunciam os
    /// comandos depois, e o menu tem de acompanhar.
    case catalogUpdated(CommandCatalog)

    case compaction(CompactionPhase)
}

public struct MappedOutput: Sendable, Equatable {

    public var events: [SessionEvent]

    public var entries: [TranscriptEntry]

    public init(events: [SessionEvent] = [], entries: [TranscriptEntry] = []) {
        self.events = events
        self.entries = entries
    }

    public static let empty = MappedOutput()
}
