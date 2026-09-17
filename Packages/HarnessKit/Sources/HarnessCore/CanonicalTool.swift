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
    /// ninguém pediu.
    public let canonical: CanonicalTool?
    public let input: JSONValue

    public init(id: String, rawName: String, canonical: CanonicalTool?, input: JSONValue) {
        self.id = id
        self.rawName = rawName
        self.canonical = canonical
        self.input = input
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
