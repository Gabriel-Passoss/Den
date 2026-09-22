import Foundation

public struct Attachment: Sendable, Equatable, Codable {

    public let kind: String
    public let path: String
    public let raw: JSONValue

    public init(kind: String, path: String, raw: JSONValue) {
        self.kind = kind
        self.path = path
        self.raw = raw
    }
}

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

public struct TurnResult: Sendable, Equatable, Codable {
    public let usage: UsageTotals
    public let stopReason: String?
    public let isError: Bool

    /// O contexto ocupado ao fechar o turno. Opcional porque transcritos
    /// gravados antes deste campo continuam decodificando.
    public let contextTokens: Int?

    public init(usage: UsageTotals, stopReason: String?, isError: Bool,
                contextTokens: Int? = nil) {
        self.usage = usage
        self.stopReason = stopReason
        self.isError = isError
        self.contextTokens = contextTokens
    }
}

public struct ContextCompaction: Sendable, Equatable, Codable {

    public enum Trigger: String, Sendable, Equatable, Codable {
        case manual, automatic
    }

    public let trigger: Trigger
    public let tokensBefore: Int
    public let tokensAfter: Int
    public let duration: TimeInterval

    public init(trigger: Trigger, tokensBefore: Int, tokensAfter: Int,
                duration: TimeInterval) {
        self.trigger = trigger
        self.tokensBefore = tokensBefore
        self.tokensAfter = tokensAfter
        self.duration = duration
    }
}

public struct TranscriptEntry: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let kind: Kind

    public let raw: JSONValue

    public init(id: UUID = UUID(), timestamp: Date, kind: Kind, raw: JSONValue) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.raw = raw
    }

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
        case contextCompacted(ContextCompaction)

        case unrecognized(discriminator: String, payload: JSONValue)

        private enum Known: Sendable, Equatable, Codable {
            case userMessage(text: String, attachments: [Attachment])
            case assistantText(String)
            case assistantThinking(String)
            case toolCall(ToolCall)
            case toolResult(ToolResult)
            case permissionRequest(PermissionRequest)
            case permissionDecision(requestID: String, PermissionDecision)
            case systemNotice(subtype: String, text: String)
            case turnResult(TurnResult)
            case contextCompacted(ContextCompaction)

            enum CodingKeys: String, CodingKey, CaseIterable {
                case userMessage, assistantText, assistantThinking, toolCall
                case toolResult, permissionRequest, permissionDecision
                case systemNotice, turnResult, contextCompacted
            }
        }

        static let knownDiscriminators: Set<String> =
            Set(Known.CodingKeys.allCases.map(\.stringValue))

        public init(from decoder: Decoder) throws {
            let peek = try decoder.container(keyedBy: DiscriminatorKey.self)
            guard peek.allKeys.count == 1, let key = peek.allKeys.first else {
                throw DecodingError.dataCorruptedError(
                    forKey: DiscriminatorKey(stringValue: "kind")!,
                    in: peek,
                    debugDescription: "TranscriptEntry.Kind espera exatamente uma chave discriminadora, achou \(peek.allKeys.count)"
                )
            }
            guard Kind.knownDiscriminators.contains(key.stringValue) else {
                let payload = try peek.decode(JSONValue.self, forKey: key)
                self = .unrecognized(discriminator: key.stringValue, payload: payload)
                return
            }
            switch try Known(from: decoder) {
            case .userMessage(let text, let attachments):
                self = .userMessage(text: text, attachments: attachments)
            case .assistantText(let text): self = .assistantText(text)
            case .assistantThinking(let text): self = .assistantThinking(text)
            case .toolCall(let call): self = .toolCall(call)
            case .toolResult(let result): self = .toolResult(result)
            case .permissionRequest(let request): self = .permissionRequest(request)
            case .permissionDecision(let requestID, let decision):
                self = .permissionDecision(requestID: requestID, decision)
            case .systemNotice(let subtype, let text):
                self = .systemNotice(subtype: subtype, text: text)
            case .turnResult(let result): self = .turnResult(result)
            case .contextCompacted(let compaction): self = .contextCompacted(compaction)
            }
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .userMessage(let text, let attachments):
                try Known.userMessage(text: text, attachments: attachments).encode(to: encoder)
            case .assistantText(let text): try Known.assistantText(text).encode(to: encoder)
            case .assistantThinking(let text): try Known.assistantThinking(text).encode(to: encoder)
            case .toolCall(let call): try Known.toolCall(call).encode(to: encoder)
            case .toolResult(let result): try Known.toolResult(result).encode(to: encoder)
            case .permissionRequest(let request): try Known.permissionRequest(request).encode(to: encoder)
            case .permissionDecision(let requestID, let decision):
                try Known.permissionDecision(requestID: requestID, decision).encode(to: encoder)
            case .systemNotice(let subtype, let text):
                try Known.systemNotice(subtype: subtype, text: text).encode(to: encoder)
            case .turnResult(let result): try Known.turnResult(result).encode(to: encoder)
            case .contextCompacted(let compaction):
                try Known.contextCompacted(compaction).encode(to: encoder)
            case .unrecognized(let discriminator, let payload):

                var container = encoder.container(keyedBy: DiscriminatorKey.self)
                try container.encode(payload, forKey: DiscriminatorKey(stringValue: discriminator)!)
            }
        }
    }
}
