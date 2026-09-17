import Foundation
import HarnessCore

/// Monta a invocação do Claude Code e declara o que ele suporta.
///
/// Tudo que é específico deste harness mora aqui e em `ClaudeDiscovery`.
public enum ClaudeLaunch {
    public static func make(
        installation: HarnessInstallation,
        workingDirectory: URL,
        sessionID: UUID,
        resuming harnessSessionID: UUID? = nil,
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
            "--session-id", sessionID.uuidString.lowercased(),
        ]
        if let harnessSessionID {
            arguments += ["--resume", harnessSessionID.uuidString.lowercased()]
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
