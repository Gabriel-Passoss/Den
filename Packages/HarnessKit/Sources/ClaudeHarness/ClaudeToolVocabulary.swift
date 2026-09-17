import HarnessCore

/// Os nomes de ferramenta deste CLI traduzidos para o vocabulário canônico da
/// spec §4.1.
///
/// Mora em `ClaudeHarness` porque é específico deste harness — e é o exemplo
/// mais limpo da regra da §7.1: `CanonicalTool` é neutro e mora no núcleo;
/// saber que este CLI chama `Bash` o que outro chamará de outra coisa é
/// conhecimento do adaptador.
///
/// A tabela cobre exatamente os nomes do array `tools` do `system/init`
/// gravado (CLI 2.1.236). Nome fora dela devolve `nil` — que é a resposta
/// honesta e a que o `ToolCall.canonical` já existe para carregar; o
/// `rawName` preserva a grafia original e o `raw` da entrada preserva o bloco
/// inteiro, então nada se perde ao não conhecer um verbo.
enum ClaudeToolVocabulary {
    static func canonical(for rawName: String) -> CanonicalTool? {
        switch rawName {
        case "Read": return .read
        case "Write": return .write
        case "Edit", "NotebookEdit": return .edit
        case "Bash": return .execute
        case "WebSearch": return .search
        case "WebFetch": return .fetch
        default: return nil
        }
    }
}
