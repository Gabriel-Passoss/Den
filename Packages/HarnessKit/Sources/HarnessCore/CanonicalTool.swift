/// Os verbos que atravessam harnesses.
///
/// Harnesses nomeiam ferramentas de forma diferente — `Edit` num, outra coisa
/// noutro — e o replay depende de significado equivalente entre eles. O
/// canônico serve ao handoff e à UI; o `rawName` e o `input` garantem que nada
/// é perdido (spec §4.1).
public enum CanonicalTool: String, Sendable, Equatable, CaseIterable, Codable {
    case read
    case write
    case edit
    case execute
    case search
    case fetch
}

/// Uma chamada de ferramenta, como o harness a pediu.
public struct ToolCall: Sendable, Equatable, Codable {
    /// O id que o harness usa para casar chamada e resultado.
    public let id: String
    /// O nome que o harness deu, preservado literalmente.
    public let rawName: String
    /// O verbo equivalente, quando existe.
    ///
    /// `nil` quando não conhecemos equivalente. É a resposta honesta: inventar
    /// um verbo faria o handoff mandar ao próximo harness uma instrução que
    /// ninguém pediu. Isso vale tanto na construção quanto na decodificação —
    /// ver `init(from:)` abaixo: um `rawValue` que este binário não conhece
    /// ainda também vira `nil`, não um erro de decodificação.
    public let canonical: CanonicalTool?
    public let input: JSONValue

    public init(id: String, rawName: String, canonical: CanonicalTool?, input: JSONValue) {
        self.id = id
        self.rawName = rawName
        self.canonical = canonical
        self.input = input
    }

    private enum CodingKeys: String, CodingKey {
        case id, rawName, canonical, input
    }

    /// Decodificador escrito à mão — a sintetização compilaria, mas jogaria
    /// fora exatamente a garantia que este tipo promete.
    ///
    /// Um transcript é lido meses depois, por um binário que pode ser mais
    /// velho do que quem o escreveu: rollback, handoff no meio de um upgrade,
    /// leitor antigo aberto contra um arquivo novo. Se uma versão futura
    /// acrescentar `CanonicalTool.delete` e gravar `"canonical":"delete"`,
    /// `CanonicalTool` sintetizado por `Decodable` trata um `rawValue`
    /// desconhecido como `DecodingError.dataCorrupted` — e isso atravessa o
    /// `Optional`: `decodeIfPresent` só devolve `nil` para chave ausente ou
    /// `null`, nunca para um valor que falhou ao analisar. O `ToolCall`
    /// inteiro falharia ao decodificar, embora "verbo que não reconhecemos"
    /// seja precisamente o caso que `canonical: nil` já existe para
    /// descrever quando o harness manda uma ferramenta nova.
    ///
    /// Por isso o campo é lido como `String?` cru e mapeado por
    /// `CanonicalTool(rawValue:)`: um `rawValue` desconhecido vira `nil` em
    /// vez de estourar. O custo: um erro real de schema nesse campo (um
    /// número em vez de string, por exemplo) ainda propaga como erro de
    /// decodificação — só o caso "string reconhecível mas verbo
    /// desconhecido" degrada. `rawName` preserva o nome original do
    /// harness, e o `TranscriptEntry.raw` da Task 2 preserva o payload
    /// inteiro; nada se perde ao degradar.
    ///
    /// Se um dia isto virar `= try container.decode(CanonicalTool.self, ...)`
    /// sintetizado, o build continua verde — só um transcript com um verbo
    /// futuro escrito por uma versão mais nova é que passa a falhar ao abrir
    /// numa mais velha. `anUnknownCanonicalVerbDegradesToNilInsteadOfFailingTheWholeDecode`
    /// é o teste que pega essa regressão.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        rawName = try container.decode(String.self, forKey: .rawName)
        let rawCanonical = try container.decodeIfPresent(String.self, forKey: .canonical)
        canonical = rawCanonical.flatMap(CanonicalTool.init(rawValue:))
        input = try container.decode(JSONValue.self, forKey: .input)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(rawName, forKey: .rawName)
        try container.encodeIfPresent(canonical?.rawValue, forKey: .canonical)
        try container.encode(input, forKey: .input)
    }
}

/// O resultado de uma chamada de ferramenta.
public struct ToolResult: Sendable, Equatable, Codable {
    /// O `ToolCall.id` a que este resultado responde.
    public let callID: String
    public let isError: Bool
    public let content: JSONValue

    public init(callID: String, isError: Bool, content: JSONValue) {
        self.callID = callID
        self.isError = isError
        self.content = content
    }
}
