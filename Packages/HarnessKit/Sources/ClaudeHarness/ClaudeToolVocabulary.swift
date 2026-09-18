import HarnessCore

/// Os nomes de ferramenta deste CLI traduzidos para o vocabulário canônico da
/// spec §4.1.
///
/// Mora em `ClaudeHarness` porque é específico deste harness — e é o exemplo
/// mais limpo da regra da §7.1: `CanonicalTool` é neutro e mora no núcleo;
/// saber que este CLI chama `Bash` o que outro chamará de outra coisa é
/// conhecimento do adaptador.
///
/// A tabela NÃO é o array `tools` do `system/init` gravado (CLI 2.1.236) — é
/// derivada dele, mas cobre mais. Essa distinção é o que mudou aqui: a versão
/// anterior deste comentário raciocinava "não adicionar nomes que esta versão
/// não emite", e essa premissa era falsa. O array `tools` é a configuração da
/// MÁQUINA que gravou a fixture, não o contrato do CLI — carrega entradas
/// específicas do plugin instalado ali (`CronCreate`, `DesignSync`,
/// `RemoteTrigger`, `EnterWorktree`, nenhuma delas com verbo canônico
/// possível) e não tem `Glob` nem `Grep`, duas ferramentas de série que mapeiam
/// sem ambiguidade para o verbo `.search` da spec §4.1. O README das fixtures
/// já avisa que `plugins`/`skills`/`slash_commands` variam por máquina;
/// `tools` está na mesma classe, só que sem aviso explícito. Sem esta entrada,
/// toda chamada `Glob`/`Grep` perderia o verbo canônico — exatamente o sinal
/// de handoff entre harnesses que esta tabela existe para carregar.
///
/// Nome fora da tabela devolve `nil` — que é a resposta honesta e a que o
/// `ToolCall.canonical` já existe para carregar; o `rawName` preserva a
/// grafia original e o `raw` da entrada preserva o bloco inteiro, então nada
/// se perde ao não conhecer um verbo.
enum ClaudeToolVocabulary {
    static func canonical(for rawName: String) -> CanonicalTool? {
        switch rawName {
        case "Read": return .read
        case "Write": return .write
        case "Edit", "NotebookEdit": return .edit
        case "Bash": return .execute
        case "WebSearch", "Glob", "Grep": return .search
        case "WebFetch": return .fetch
        default: return nil
        }
    }
}
