import Foundation

/// Como o próximo segmento foi semeado ao trocar de harness.
///
/// As duas estratégias da spec §3: o usuário escolhe entre um briefing gerado
/// e o replay do transcript.
public enum Handoff: Sendable, Equatable, Codable {
    /// Um resumo estruturado, gerado a partir do transcript anterior.
    case briefing(String)
    /// O transcript reinjetado até uma entrada específica, inclusive.
    ///
    /// Referencia a entrada por id e não por índice: índices se deslocam,
    /// ids não.
    case replay(throughEntry: UUID)
}

/// Um trecho contínuo de conversa dentro de um harness.
public struct Segment: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let harness: HarnessID
    /// O `--session-id` que NÓS geramos e demos ao harness.
    public let harnessSessionID: UUID
    public var model: String
    public var entries: [TranscriptEntry]
    /// Tokens e custo deste trecho. Fica aqui, e não na sessão, porque tokens
    /// acabam por provedor.
    public var usage: UsageTotals
    /// Como este segmento foi semeado, quando veio de uma troca de harness.
    /// `nil` no primeiro segmento de uma sessão.
    public var seededBy: Handoff?

    public init(id: UUID = UUID(), harness: HarnessID, harnessSessionID: UUID,
                model: String, entries: [TranscriptEntry] = [],
                usage: UsageTotals = .zero, seededBy: Handoff? = nil) {
        self.id = id
        self.harness = harness
        self.harnessSessionID = harnessSessionID
        self.model = model
        self.entries = entries
        self.usage = usage
        self.seededBy = seededBy
    }
}

/// O que o usuário chama de "a conversa".
///
/// **Uma sessão do DevSpace não é uma sessão do harness.** Trocar de um
/// harness para outro fecha um `Segment` e abre outro dentro desta mesma
/// `Session`; o transcript é a concatenação deles e a proveniência da troca
/// fica em `Segment.seededBy` (spec §4.2).
public struct Session: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public var title: String
    public var workingDirectory: URL
    /// Ordenados. O primeiro é o mais antigo.
    public var segments: [Segment]

    public init(id: UUID = UUID(), title: String, workingDirectory: URL,
                segments: [Segment] = []) {
        self.id = id
        self.title = title
        self.workingDirectory = workingDirectory
        self.segments = segments
    }

    /// O transcript inteiro, atravessando harnesses.
    public var allEntries: [TranscriptEntry] {
        segments.flatMap(\.entries)
    }

    /// Custo somado de todos os segmentos.
    public var totalUsage: UsageTotals {
        segments.reduce(.zero) { $0 + $1.usage }
    }
}

/// O bastante para listar uma sessão sem carregar o transcript dela.
public struct SessionSummary: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public var title: String
    public var workingDirectory: URL
    /// Na ordem em que apareceram na conversa.
    public var harnesses: [HarnessID]
    public var usage: UsageTotals
    public var entryCount: Int
    public var updatedAt: Date

    public init(id: UUID, title: String, workingDirectory: URL, harnesses: [HarnessID],
                usage: UsageTotals, entryCount: Int, updatedAt: Date) {
        self.id = id
        self.title = title
        self.workingDirectory = workingDirectory
        self.harnesses = harnesses
        self.usage = usage
        self.entryCount = entryCount
        self.updatedAt = updatedAt
    }

    /// Deriva de uma `Session` tudo que É derivável de metadado —
    /// `id`, `title`, `workingDirectory`, `harnesses`, `usage` — e exige
    /// `entryCount` como parâmetro em vez de calculá-lo internamente.
    ///
    /// A razão é o próprio propósito deste tipo: "listar uma sessão sem
    /// carregar o transcript dela." A Task 4 carrega sessões desse jeito —
    /// os segmentos vêm com `usage`, `harness` e `seededBy` preenchidos, mas
    /// `entries: []`, porque as entradas moram em arquivos NDJSON separados
    /// por design. Se este inicializador calculasse `entryCount` a partir de
    /// `session.allEntries.count`, ele reportaria zero exatamente no cenário
    /// em que este tipo existe para ser usado — uma sessão com centenas de
    /// entradas relatada como vazia. `usage` não sofre desse problema porque
    /// mora diretamente em `Segment`, independente de os `entries` estarem
    /// carregados; só `entryCount` pode mentir. Por isso ele não é derivado
    /// aqui: um chamador com a sessão inteira carregada passa
    /// `session.allEntries.count` e diz isso explicitamente no call site; um
    /// chamador com só metadado passa a contagem de onde quer que ele
    /// realmente a conheça (por exemplo, do índice persistido).
    public init(session: Session, entryCount: Int, updatedAt: Date) {
        self.init(id: session.id, title: session.title,
                  workingDirectory: session.workingDirectory,
                  harnesses: session.segments.map(\.harness),
                  usage: session.totalUsage,
                  entryCount: entryCount,
                  updatedAt: updatedAt)
    }
}
