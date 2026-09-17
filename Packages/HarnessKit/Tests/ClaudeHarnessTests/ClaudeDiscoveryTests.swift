import Testing
import Foundation
import HarnessCore
@testable import ClaudeHarness

extension Tag {
    @Tag static var integration: Self
}

/// Runner falso: mapeia comando+args para uma saída fixa, ou lança se não mapeado.
///
/// `failures` existe para separar os dois modos de falha que a descoberta trata
/// de formas diferentes: um caminho que nem chega a executar (o `NSError`
/// abaixo, análogo ao que `Process.run()` lança para um executável ausente) e um
/// binário que **executou** e saiu com erro (`CommandFailure`, com stderr).
struct FakeCommandRunner: CommandRunner {
    var responses: [String: String] = [:]
    var failures: [String: CommandFailure] = [:]

    func run(_ executable: String, _ arguments: [String]) async throws -> String {
        let key = ([executable] + arguments).joined(separator: " ")
        if let failure = failures[key] { throw failure }
        guard let out = responses[key] else {
            throw NSError(domain: "fake", code: 127)
        }
        return out
    }
}

@Test func findsTheBinaryViaTheLoginShell() async throws {
    let runner = FakeCommandRunner(responses: [
        "/bin/zsh -l -c command -v claude": "/opt/homebrew/bin/claude\n",
        "/opt/homebrew/bin/claude --version": "2.1.236 (Claude Code)\n",
    ])
    let install = try await ClaudeDiscovery(runner: runner, shell: "/bin/zsh", fallbackPaths: []).discover()
    #expect(install.executable == "/opt/homebrew/bin/claude")
    #expect(install.version == "2.1.236")
}

@Test func fallsBackWhenTheShellFindsNothing() async throws {
    let runner = FakeCommandRunner(responses: [
        "/usr/local/bin/claude --version": "2.0.9 (Claude Code)\n",
    ])
    let install = try await ClaudeDiscovery(
        runner: runner, shell: "/bin/zsh", fallbackPaths: ["/usr/local/bin/claude"]
    ).discover()
    #expect(install.executable == "/usr/local/bin/claude")
    #expect(install.version == "2.0.9")
}

@Test func failsWithNotFoundWhenNothingResponds() async {
    let runner = FakeCommandRunner()
    await #expect(throws: ClaudeDiscovery.DiscoveryError.notFound) {
        _ = try await ClaudeDiscovery(runner: runner, shell: "/bin/zsh", fallbackPaths: []).discover()
    }
}

@Test func failsWhenTheVersionIsUnreadable() async {
    let runner = FakeCommandRunner(responses: [
        "/bin/zsh -l -c command -v claude": "/opt/homebrew/bin/claude\n",
        "/opt/homebrew/bin/claude --version": "não sou uma versão\n",
    ])
    await #expect(throws: ClaudeDiscovery.DiscoveryError.unreadableVersion("não sou uma versão")) {
        _ = try await ClaudeDiscovery(runner: runner, shell: "/bin/zsh", fallbackPaths: []).discover()
    }
}

// Ruling B: um candidato com versão ilegível não pode abortar a busca — os
// fallbacks seguintes ainda precisam ter a vez, e a falha registrada é
// descartada assim que algum candidato funciona.
@Test func discardsAVersionFailureWhenAFallbackWorks() async throws {
    let runner = FakeCommandRunner(responses: [
        "/opt/homebrew/bin/claude --version": "não sou uma versão\n",
        "/usr/local/bin/claude --version": "2.0.9 (Claude Code)\n",
    ])
    let install = try await ClaudeDiscovery(
        runner: runner,
        shell: "/bin/zsh",
        fallbackPaths: ["/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
    ).discover()
    #expect(install.executable == "/usr/local/bin/claude")
    #expect(install.version == "2.0.9")
}

/// Um `claude` instalado mas quebrado (node ausente, shim falhando, EACCES,
/// sessão não autenticada) era reportado como `.notFound` — "não instalado" —
/// sobre um binário que está ali, e o stderr que dizia o porquê era jogado fora
/// pelo `catch` genérico. A spec §5.3 conta com essa evidência: `AuthFailure` é
/// "a causa mais provável de falha inicial" e não tem outra origem.
@Test func preservesStderrFromABinaryThatExistsButFails() async {
    let runner = FakeCommandRunner(
        responses: ["/bin/zsh -l -c command -v claude": "/opt/homebrew/bin/claude\n"],
        failures: [
            "/opt/homebrew/bin/claude --version":
                CommandFailure(exitCode: 1, stderr: "Invalid API key · Run /login")
        ]
    )
    await #expect(throws: ClaudeDiscovery.DiscoveryError.versionCommandFailed(
        exitCode: 1, stderr: "Invalid API key · Run /login"
    )) {
        _ = try await ClaudeDiscovery(runner: runner, shell: "/bin/zsh", fallbackPaths: []).discover()
    }
}

/// Mesma regra do Ruling B, aplicada à falha nova: um candidato quebrado no meio
/// da lista não pode abortar a busca nem sobreviver a um sucesso posterior.
@Test func discardsACommandFailureWhenAFallbackWorks() async throws {
    let runner = FakeCommandRunner(
        responses: ["/usr/local/bin/claude --version": "2.0.9 (Claude Code)\n"],
        failures: [
            "/opt/homebrew/bin/claude --version": CommandFailure(exitCode: 126, stderr: "permission denied")
        ]
    )
    let install = try await ClaudeDiscovery(
        runner: runner,
        shell: "/bin/zsh",
        fallbackPaths: ["/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
    ).discover()
    #expect(install.executable == "/usr/local/bin/claude")
}

@Test func doesNotResolveTheSymlinkToTheVersionedPath() async throws {
    // O caminho lógico precisa sobreviver a um `brew upgrade` (spec §4.4):
    // resolver o symlink perderia esse caminho na próxima atualização. Um
    // teste que só olhasse para "não contém Caskroom" não pinaria isso — a
    // string fake nunca teria "Caskroom" mesmo se `discover()` resolvesse
    // symlinks de verdade. Aqui criamos um symlink real apontando para um
    // alvo versionado real, e verificamos que o caminho devolvido é o
    // symlink, não o alvo resolvido.
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let versionedDir = tempDir.appendingPathComponent("Caskroom/claude-code/2.1.236")
    try FileManager.default.createDirectory(at: versionedDir, withIntermediateDirectories: true)
    let versionedTarget = versionedDir.appendingPathComponent("claude")
    #expect(FileManager.default.createFile(atPath: versionedTarget.path, contents: Data()))

    let symlinkPath = tempDir.appendingPathComponent("claude")
    try FileManager.default.createSymbolicLink(at: symlinkPath, withDestinationURL: versionedTarget)

    let runner = FakeCommandRunner(responses: [
        "/bin/zsh -l -c command -v claude": symlinkPath.path + "\n",
        "\(symlinkPath.path) --version": "2.1.236 (Claude Code)\n",
    ])
    let install = try await ClaudeDiscovery(runner: runner, shell: "/bin/zsh", fallbackPaths: []).discover()

    #expect(install.executable == symlinkPath.path)
    #expect(!install.executable.contains("Caskroom"))
}

// Ruling C: a tag sozinha só filtra, não desliga por padrão — por isso o
// `.enabled(if:)` explícito. Sem HARNESSKIT_INTEGRATION=1 este teste não roda.
@Test(.tags(.integration), .enabled(if: ProcessInfo.processInfo.environment["HARNESSKIT_INTEGRATION"] != nil))
func findsTheRealClaude() async throws {
    let install = try await ClaudeDiscovery().discover()
    #expect(install.executable.hasSuffix("claude"))
    #expect(!install.version.isEmpty)
}
