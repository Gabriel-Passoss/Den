import Testing
import Foundation
import HarnessCore
@testable import ClaudeHarness

extension Tag {
    @Tag static var integration: Self
}

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
        "/opt/homebrew/bin/claude --version": "not a version\n",
    ])
    await #expect(throws: ClaudeDiscovery.DiscoveryError.unreadableVersion("not a version")) {
        _ = try await ClaudeDiscovery(runner: runner, shell: "/bin/zsh", fallbackPaths: []).discover()
    }
}

@Test func discardsAVersionFailureWhenAFallbackWorks() async throws {
    let runner = FakeCommandRunner(responses: [
        "/opt/homebrew/bin/claude --version": "not a version\n",
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

@Test(.tags(.integration), .enabled(if: ProcessInfo.processInfo.environment["HARNESSKIT_INTEGRATION"] != nil))
func findsTheRealClaude() async throws {
    let install = try await ClaudeDiscovery().discover()
    #expect(install.executable.hasSuffix("claude"))
    #expect(!install.version.isEmpty)
}
