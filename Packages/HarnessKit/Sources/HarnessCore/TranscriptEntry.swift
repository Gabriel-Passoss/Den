import Foundation

/// Um anexo de uma mensagem do usuário.
public struct Attachment: Sendable, Equatable, Codable {
    /// Como o harness classificou o anexo ("image", "file", …), literal.
    public let kind: String
    public let path: String
    public let raw: JSONValue

    public init(kind: String, path: String, raw: JSONValue) {
        self.kind = kind
        self.path = path
        self.raw = raw
    }
}

/// Contabilidade de tokens e custo.
///
/// Fica por segmento e é agregada por sessão, porque tokens acabam POR
/// PROVEDOR — que é a razão original de existir a troca de harness (spec §4.2).
public struct UsageTotals: Sendable, Equatable, Codable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadTokens: Int
    public var cacheCreationTokens: Int
    public var costUSD: Double

    public init(inputTokens: Int = 0, outputTokens: Int = 0, cacheReadTokens: Int = 0,
                cacheCreationTokens: Int = 0, costUSD: Double = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.costUSD = costUSD
    }

    public static let zero = UsageTotals()

    public static func + (lhs: UsageTotals, rhs: UsageTotals) -> UsageTotals {
        UsageTotals(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            cacheReadTokens: lhs.cacheReadTokens + rhs.cacheReadTokens,
            cacheCreationTokens: lhs.cacheCreationTokens + rhs.cacheCreationTokens,
            costUSD: lhs.costUSD + rhs.costUSD
        )
    }
}

/// Como um turno terminou.
public struct TurnResult: Sendable, Equatable, Codable {
    public let usage: UsageTotals
    public let stopReason: String?
    public let isError: Bool

    public init(usage: UsageTotals, stopReason: String?, isError: Bool) {
        self.usage = usage
        self.stopReason = stopReason
        self.isError = isError
    }
}

/// Uma entrada do transcript.
///
/// Semântica, não visual: a spec §4.2 exige um registro semântico FIEL, porque
/// o replay para outro harness depende de ele ser completo. Cada entrada
/// carrega o payload original em `raw` — o canônico serve ao handoff e à UI, o
/// raw garante que nada é perdido.
public struct TranscriptEntry: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let kind: Kind
    /// O payload original do harness, na íntegra.
    public let raw: JSONValue

    public init(id: UUID = UUID(), timestamp: Date, kind: Kind, raw: JSONValue) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.raw = raw
    }

    /// Os nove casos da spec §4.2.
    public enum Kind: Sendable, Equatable, Codable {
        case userMessage(text: String, attachments: [Attachment])
        case assistantText(String)
        case assistantThinking(String)
        case toolCall(ToolCall)
        case toolResult(ToolResult)
        case permissionRequest(PermissionRequest)
        case permissionDecision(requestID: String, PermissionDecision)
        case systemNotice(subtype: String, text: String)
        case turnResult(TurnResult)
    }
}
