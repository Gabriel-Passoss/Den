import Foundation

public struct HarnessInstallation: Equatable, Sendable {
    /// Caminho lógico, nunca o alvo resolvido do symlink: o Homebrew aponta
    /// para um diretório versionado que muda a cada atualização (spec §4.4).
    public let executable: String
    public let version: String

    public init(executable: String, version: String) {
        self.executable = executable
        self.version = version
    }
}

public struct ClaudeDiscovery: Sendable {
    public enum DiscoveryError: Error, Equatable {
        case notFound
        case unreadableVersion(String)
    }

    public static let defaultFallbackPaths = [
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        NSHomeDirectory() + "/.local/bin/claude",
        NSHomeDirectory() + "/.claude/local/claude",
    ]

    private let runner: CommandRunner
    private let shell: String
    private let fallbackPaths: [String]

    public init(
        runner: CommandRunner = SystemCommandRunner(),
        shell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
        fallbackPaths: [String] = ClaudeDiscovery.defaultFallbackPaths
    ) {
        self.runner = runner
        self.shell = shell
        self.fallbackPaths = fallbackPaths
    }

    public func discover() async throws -> HarnessInstallation {
        // Guarda o primeiro `unreadableVersion` encontrado: um binário que
        // existe mas cuja versão não dá para ler é uma falha acionável,
        // diferente de "não instalado" — mas um candidato ruim no meio da
        // lista não pode impedir que os fallbacks seguintes sejam tentados.
        var firstUnreadableVersion: DiscoveryError?
        for candidate in try await candidates() {
            do {
                let version = try await readVersion(of: candidate)
                return HarnessInstallation(executable: candidate, version: version)
            } catch let error as DiscoveryError {
                if firstUnreadableVersion == nil, case .unreadableVersion = error {
                    firstUnreadableVersion = error
                }
                continue
            } catch {
                continue
            }
        }
        throw firstUnreadableVersion ?? DiscoveryError.notFound
    }

    /// Um app aberto pelo Finder não herda o PATH do shell, então perguntamos
    /// ao shell de login antes de tentar os caminhos conhecidos (spec §4.4).
    private func candidates() async throws -> [String] {
        var found: [String] = []
        if let output = try? await runner.run(shell, ["-l", "-c", "command -v claude"]) {
            let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty { found.append(path) }
        }
        found.append(contentsOf: fallbackPaths)
        return found
    }

    private func readVersion(of executable: String) async throws -> String {
        let raw = try await runner.run(executable, ["--version"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Formato observado: "2.1.236 (Claude Code)"
        guard let match = raw.firstMatch(of: /^(\d+\.\d+\.\d+)/) else {
            throw DiscoveryError.unreadableVersion(raw)
        }
        return String(match.1)
    }
}
