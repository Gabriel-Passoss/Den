import Testing
import Foundation
@testable import ClaudeHarness

extension Tag {
    @Tag static var integration: Self
}

/// Runner falso: mapeia comando+args para uma saída fixa, ou lança se não mapeado.
struct FakeCommandRunner: CommandRunner {
    var responses: [String: String] = [:]
    func run(_ executable: String, _ arguments: [String]) async throws -> String {
        let key = ([executable] + arguments).joined(separator: " ")
        guard let out = responses[key] else {
            throw NSError(domain: "fake", code: 127)
        }
        return out
    }
}

@Test func achaOBinarioPeloShellDeLogin() async throws {
    let runner = FakeCommandRunner(responses: [
        "/bin/zsh -l -c command -v claude": "/opt/homebrew/bin/claude\n",
        "/opt/homebrew/bin/claude --version": "2.1.236 (Claude Code)\n",
    ])
    let install = try await ClaudeDiscovery(runner: runner, shell: "/bin/zsh", fallbackPaths: []).discover()
    #expect(install.executable == "/opt/homebrew/bin/claude")
    #expect(install.version == "2.1.236")
}

@Test func caiNoFallbackQuandoOShellNaoAcha() async throws {
    let runner = FakeCommandRunner(responses: [
        "/usr/local/bin/claude --version": "2.0.9 (Claude Code)\n",
    ])
    let install = try await ClaudeDiscovery(
        runner: runner, shell: "/bin/zsh", fallbackPaths: ["/usr/local/bin/claude"]
    ).discover()
    #expect(install.executable == "/usr/local/bin/claude")
    #expect(install.version == "2.0.9")
}

@Test func falhaComNotFoundQuandoNadaResponde() async {
    let runner = FakeCommandRunner()
    await #expect(throws: ClaudeDiscovery.DiscoveryError.notFound) {
        _ = try await ClaudeDiscovery(runner: runner, shell: "/bin/zsh", fallbackPaths: []).discover()
    }
}

@Test func falhaQuandoAVersaoNaoEhLegivel() async {
    let runner = FakeCommandRunner(responses: [
        "/bin/zsh -l -c command -v claude": "/opt/homebrew/bin/claude\n",
        "/opt/homebrew/bin/claude --version": "não sou uma versão\n",
    ])
    await #expect(throws: ClaudeDiscovery.DiscoveryError.unreadableVersion("não sou uma versão")) {
        _ = try await ClaudeDiscovery(runner: runner, shell: "/bin/zsh", fallbackPaths: []).discover()
    }
}

@Test func naoResolveOSymlinkParaOCaminhoVersionado() async throws {
    // O caminho lógico precisa sobreviver a um `brew upgrade` (spec §4.4).
    let runner = FakeCommandRunner(responses: [
        "/bin/zsh -l -c command -v claude": "/opt/homebrew/bin/claude\n",
        "/opt/homebrew/bin/claude --version": "2.1.236 (Claude Code)\n",
    ])
    let install = try await ClaudeDiscovery(runner: runner, shell: "/bin/zsh", fallbackPaths: []).discover()
    #expect(!install.executable.contains("Caskroom"))
}

// Ruling C: a tag sozinha só filtra, não desliga por padrão — por isso o
// `.enabled(if:)` explícito. Sem HARNESSKIT_INTEGRATION=1 este teste não roda.
@Test(.tags(.integration), .enabled(if: ProcessInfo.processInfo.environment["HARNESSKIT_INTEGRATION"] != nil))
func achaOClaudeDeVerdade() async throws {
    let install = try await ClaudeDiscovery().discover()
    #expect(install.executable.hasSuffix("claude"))
    #expect(!install.version.isEmpty)
}
