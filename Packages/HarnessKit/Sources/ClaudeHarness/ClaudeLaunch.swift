import Foundation
import HarnessCore

/// Como uma sessão do Claude Code começa.
///
/// Existe porque `--resume <id>` sozinho já retoma a sessão original —
/// `claude --help` documenta `--fork-session` como o que muda esse
/// comportamento ("When resuming, create a new session ID instead of
/// reusing the original"). Um `make(...)` que sempre emitisse
/// `--session-id <novo>` junto de `--resume <antigo>` produziria um argv
/// incoerente: diz "use este id novo" e "continue a sessão antiga sem
/// bifurcar" ao mesmo tempo — exatamente o defeito que um `Bool
/// forkSession` solto deixaria construível. Modelar os três casos aqui
/// torna essa combinação irrepresentável, em vez de meramente evitada por
/// convenção de quem chama.
public enum SessionStart: Sendable, Equatable {
    /// Sessão nova. Nós geramos o id.
    case fresh(sessionID: UUID)
    /// Retomar a MESMA sessão do harness — o ciclo idle → hot da spec §5.1.
    /// Não passamos --session-id: a identidade é a que está sendo retomada.
    case resume(harnessSessionID: UUID)
    /// Bifurcar a partir de uma sessão existente, criando uma identidade nova.
    case fork(from: UUID, newSessionID: UUID)
}

/// Monta a invocação do Claude Code e declara o que ele suporta.
///
/// Tudo que é específico deste harness mora aqui e em `ClaudeDiscovery`.
public enum ClaudeLaunch {
    public static func make(
        installation: HarnessInstallation,
        workingDirectory: URL,
        session: SessionStart,
        model: String? = nil,
        permissionMode: String? = nil,
        additionalDirectories: [URL] = []
    ) -> ProcessTransport.Launch {
        var arguments = [
            "-p",
            "--output-format", "stream-json",
            "--input-format", "stream-json",
            "--include-partial-messages",
            "--verbose",
            // A flag que faz o CLI PERGUNTAR em vez de decidir sozinho. Não
            // aparece em `claude --help`; foi encontrada no código do binário
            // 2.1.236 e confirmada no SDK oficial. Sem ela, nenhum
            // control_request de can_use_tool chega — ver
            // docs/superpowers/notes-2026-09-17-protocolo-observado.md
            "--permission-prompt-tool", "stdio",
        ]

        switch session {
        case .fresh(let sessionID):
            arguments += ["--session-id", sessionID.uuidString.lowercased()]
        case .resume(let harnessSessionID):
            // Sem --session-id aqui, de propósito: --resume sozinho já
            // retoma a identidade antiga (ver a doc de SessionStart).
            arguments += ["--resume", harnessSessionID.uuidString.lowercased()]
        case .fork(let from, let newSessionID):
            arguments += [
                "--resume", from.uuidString.lowercased(),
                "--fork-session",
                "--session-id", newSessionID.uuidString.lowercased(),
            ]
        }

        if let model { arguments += ["--model", model] }
        if let permissionMode { arguments += ["--permission-mode", permissionMode] }
        for directory in additionalDirectories {
            arguments += ["--add-dir", directory.path]
        }

        var environment = ProcessInfo.processInfo.environment
        // O SDK oficial anuncia a si mesmo assim (`sdk-py`, `sdk-ts`). Anunciar
        // o DevSpace mantém a telemetria do harness honesta sobre quem o chamou.
        environment["CLAUDE_CODE_ENTRYPOINT"] = "devspace"

        return ProcessTransport.Launch(
            executable: installation.executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment
        )
    }

    /// O que o Claude Code suporta quando lançado por `make(...)`.
    ///
    /// `routesPermissionRequests` é verdadeiro porque `make` passa
    /// `--permission-prompt-tool stdio`. Se a flag sair dali, esta declaração
    /// vira mentira — as duas coisas andam juntas.
    ///
    /// `canSetModelInSession` é `false`: `set_model` existe no protocolo, mas
    /// não foi verificado contra o CLI real. Declarar `false` é a resposta
    /// conservadora que a spec §4.1 pede — a UI esconde o botão até alguém
    /// confirmar que funciona.
    ///
    /// `canResumeSession` e `canForkSession` são `true` num pé diferente de
    /// `canSetModelInSession`, mas ainda incompleto: `--resume` e
    /// `--fork-session` estão documentados em `claude --help` (diferente de
    /// `set_model`, que só aparece no protocolo), e `SessionStart` tem teste
    /// de unidade para cada caso — mas nenhuma sessão gravada exercitou um
    /// resume ou um fork de ponta a ponta ainda. "Documentado e testado na
    /// construção do argv" não é o mesmo que "verificado contra o CLI real".
    /// O que assentaria isso: um fixture gravado de uma sessão de resume,
    /// nos moldes de `permission-request.ndjson`.
    ///
    /// `installation` não é lido hoje porque a declaração é constante para
    /// qualquer build do Claude Code — o parâmetro fica reservado de
    /// propósito para o dia em que capacidades variarem por versão, sem
    /// precisar mudar a assinatura no ponto de chamada.
    public static func capabilities(for installation: HarnessInstallation) -> HarnessCapabilities {
        HarnessCapabilities(
            routesPermissionRequests: true,
            canInterrupt: true,
            canSetPermissionMode: true,
            canSetModelInSession: false,
            canResumeSession: true,
            canForkSession: true
        )
    }
}
