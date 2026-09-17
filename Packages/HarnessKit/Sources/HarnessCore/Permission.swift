/// Um pedido de permissão vindo de um harness.
///
/// Mora em `HarnessCore`, e não num adaptador, pelo teste da spec §7.1: o tipo
/// não nomeia harness nenhum, e um segundo adaptador necessariamente
/// precisaria dele — toda sessão tem que perguntar antes de usar uma
/// ferramenta, e a UI precisa de **um** tipo de pedido ou vira um diálogo por
/// harness. A spec §4.1 já o declarava aqui, na assinatura
/// `HarnessSession.resolve(_ request: PermissionRequest.ID, _ d:
/// PermissionDecision)`.
///
/// A leitura do formato de fio de cada CLI fica no adaptador, como extensão.
/// É a mesma forma que a Task 1 usou para `ProcessTransport`: o valor é
/// neutro, a codificação é específica.
public struct PermissionRequest: Equatable, Sendable {
    public let id: String
    public let toolName: String
    public let displayName: String?
    public let description: String?
    public let input: JSONValue
    public let toolUseID: String?
    /// Regras que o próprio harness sugere — material direto para os botões do
    /// diálogo ("permitir sempre nesta sessão") em vez de inventarmos os nossos.
    public let suggestions: [PermissionSuggestion]

    public init(
        id: String,
        toolName: String,
        displayName: String? = nil,
        description: String? = nil,
        input: JSONValue = .null,
        toolUseID: String? = nil,
        suggestions: [PermissionSuggestion] = []
    ) {
        self.id = id
        self.toolName = toolName
        self.displayName = displayName
        self.description = description
        self.input = input
        self.toolUseID = toolUseID
        self.suggestions = suggestions
    }
}

/// Uma regra que o harness sugere junto do pedido.
public struct PermissionSuggestion: Equatable, Sendable {
    public let type: String?
    public let mode: String?
    public let destination: String?
    public let behavior: String?
    /// Payload original preservado — nem todo campo de sugestão é conhecido.
    /// Controller ruling (Finding 3): uma sugestão sem "type" ainda é
    /// preservada aqui, não descartada — um diálogo que ignora o que não
    /// entende é melhor que um `suggestions.count` que mente sobre o que o
    /// harness realmente ofereceu.
    public let raw: JSONValue

    public init(
        type: String? = nil,
        mode: String? = nil,
        destination: String? = nil,
        behavior: String? = nil,
        raw: JSONValue = .null
    ) {
        self.type = type
        self.mode = mode
        self.destination = destination
        self.behavior = behavior
        self.raw = raw
    }
}

/// O que o usuário decidiu sobre um pedido de permissão.
///
/// Mesmo teste da §7.1, e o caso é ainda mais claro: o tipo diz `allow` e
/// `deny`, palavras de ninguém em particular. Enquanto ele morava no módulo de
/// um harness específico, um segundo adaptador tinha que importar esse módulo
/// só para dizer a palavra "allow" — exatamente o modo de falha que a §7.1
/// matou uma camada abaixo, reaparecendo uma camada acima.
public enum PermissionDecision: Equatable, Sendable {
    case allow(updatedInput: JSONValue?)
    case deny(message: String, interrupt: Bool)
}

/// O modo de permissão de uma sessão.
///
/// Conjunto fechado, e não `String`, pela mesma razão que fez `SessionStart`
/// nascer: um modo com typo é um erro do CLI em tempo de execução — a sessão
/// sobe, falha lá adiante, e a mensagem vem do processo filho. Os seis valores
/// são os verificados na spec §12.
///
/// O `rawValue` é a grafia canônica do conceito, e hoje coincide com a que o
/// primeiro harness aceita na linha de comando. É o adaptador quem faz essa
/// tradução: se um segundo harness soletrar os mesmos modos de outro jeito, o
/// mapeamento muda lá, não aqui.
public enum PermissionMode: String, Equatable, Sendable, CaseIterable {
    case acceptEdits
    case auto
    case bypassPermissions
    case manual
    case dontAsk
    case plan
}
