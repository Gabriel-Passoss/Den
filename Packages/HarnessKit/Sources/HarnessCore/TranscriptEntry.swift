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

    /// Os nove casos da spec §4.2, mais um décimo de fuga.
    ///
    /// Decodificador escrito à mão pelo mesmo motivo do `ToolCall.init(from:)`
    /// da Task 1, uma camada acima e com um raio de dano maior: a sintetização
    /// chavearia o container externo pelo nome do caso, e um discriminador que
    /// este binário não conhece — `{"kind": {"subagentSpawn": {...}}}`, gravado
    /// por uma versão futura — estouraria `DecodingError` para a
    /// `TranscriptEntry` INTEIRA. Isso derruba `id`, `timestamp` e `raw`
    /// junto, quando `raw` está bem ali no mesmo objeto JSON, guardando os
    /// bytes exatos que preservariam o registro. Contradiria a garantia da
    /// própria doc acima: "raw garante que nada é perdido" — exceto quando
    /// perde tudo.
    ///
    /// Por isso um discriminador desconhecido degrada para `.unrecognized`
    /// (discriminador + payload como `JSONValue`) em vez de propagar o erro —
    /// mesma disciplina de escopo do `ToolCall`: só esse caso específico
    /// degrada; um JSON genuinamente corrompido (chave `kind` ausente, ou não
    /// sendo um objeto de uma chave só) continua estourando `DecodingError`
    /// de verdade.
    ///
    /// Requisito de idempotência: reencode de um `.unrecognized` PRECISA
    /// reemitir o discriminador e o payload originais, nunca a palavra
    /// "unrecognized". Cenário: uma versão nova grava um décimo caso; um
    /// binário mais velho abre, degrada para `.unrecognized("subagentSpawn",
    /// ...)`, e depois regrava a sessão por qualquer motivo (compactação,
    /// migração). Se o encoder escrevesse `{"unrecognized": {...}}`, o
    /// registro ficaria degradado PERMANENTEMENTE — inclusive para a versão
    /// nova, que entende "subagentSpawn" perfeitamente bem e deixaria de
    /// reconhecer o próprio caso que ela escreveu. Não "simplifique" o
    /// encoder de volta para escrever o nome do caso — é exatamente essa
    /// simplificação que quebra a idempotência.
    /// `decodingAnUnknownCaseAndReencodingItIsIdempotent` é o teste que pega
    /// essa regressão.
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
        /// Um caso que esta versão não conhece, preservado em vez de perdido.
        case unrecognized(discriminator: String, payload: JSONValue)

        /// Espelho dos nove casos conhecidos, com o mesmo formato de fio que
        /// `Kind` teria se sua `Codable` fosse inteiramente sintetizada
        /// (mesmos nomes de caso, mesmos rótulos de valor associado, mesma
        /// ordem). Existe só para emprestar essa sintetização: decodificar
        /// aqui é decodificar exatamente como o compilador decodificaria os
        /// nove casos de `Kind`, sem reescrever à mão o container aninhado de
        /// cada um.
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

            /// Escrita à mão, byte por byte igual à que o compilador
            /// sintetizaria — verificado: o formato de fio não muda por
            /// declará-la. Existe para que `knownDiscriminators` abaixo possa
            /// ser DERIVADO dela em vez de ser uma segunda lista de strings
            /// mantida à mão ao lado dos casos.
            enum CodingKeys: String, CodingKey, CaseIterable {
                case userMessage, assistantText, assistantThinking, toolCall
                case toolResult, permissionRequest, permissionDecision
                case systemNotice, turnResult
            }
        }

        /// Os discriminadores que esta versão conhece, derivados das MESMAS
        /// chaves que a `Codable` sintetizada de `Known` usa para ler e
        /// escrever — não uma lista paralela.
        ///
        /// A cadeia `Kind` → `Known` → `Known.CodingKeys` tem os dois
        /// primeiros elos impostos pelo compilador: um décimo caso em `Kind`
        /// quebra o `switch` de `encode(to:)` (exaustivo), a correção dele
        /// exige o caso em `Known`, e isso por sua vez quebra o `switch` de
        /// `init(from:)` (exaustivo sobre `Known`). O terceiro elo —
        /// `Known` → `CodingKeys` — NÃO é imposto pelo compilador (medido:
        /// compila, e `encode` estoura em tempo de execução com "Case 'x'
        /// cannot be encoded because it is not defined in CodingKeys"). Quem
        /// fecha esse elo é `theOpenEnumsDoNotDivergeFromTheirKnownDiscriminators`
        /// em `TranscriptFormatGoldenTests.swift`.
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
            case .unrecognized(let discriminator, let payload):
                // Reemite o discriminador e o payload originais — ver o
                // requisito de idempotência na doc do tipo acima.
                var container = encoder.container(keyedBy: DiscriminatorKey.self)
                try container.encode(payload, forKey: DiscriminatorKey(stringValue: discriminator)!)
            }
        }
    }
}
