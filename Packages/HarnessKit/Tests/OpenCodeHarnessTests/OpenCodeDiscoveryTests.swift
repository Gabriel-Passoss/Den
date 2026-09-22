import Testing
import Foundation
import HarnessCore
@testable import OpenCodeHarness

private struct FakeCommandRunner: CommandRunner {
    var responses: [String: String] = [:]
    var failures: [String: CommandFailure] = [:]

    func run(_ executable: String, _ arguments: [String]) async throws -> String {
        let key = ([executable] + arguments).joined(separator: " ")
        if let failure = failures[key] { throw failure }
        guard let out = responses[key] else { throw NSError(domain: "fake", code: 127) }
        return out
    }
}

@Test func findsTheBinaryViaTheLoginShell() async throws {
    let runner = FakeCommandRunner(responses: [
        "/bin/zsh -l -c command -v opencode": "/opt/homebrew/bin/opencode\n",

        "/opt/homebrew/bin/opencode --version": "1.18.31\n",
    ])
    let install = try await OpenCodeDiscovery(
        runner: runner, shell: "/bin/zsh", fallbackPaths: []).discover()
    #expect(install.executable == "/opt/homebrew/bin/opencode")
    #expect(install.version == "1.18.31")
}

@Test func fallsBackWhenTheShellFindsNothing() async throws {
    let runner = FakeCommandRunner(responses: [
        "\(NSHomeDirectory())/.opencode/bin/opencode --version": "1.17.0\n",
    ])
    let install = try await OpenCodeDiscovery(
        runner: runner, shell: "/bin/zsh",
        fallbackPaths: ["\(NSHomeDirectory())/.opencode/bin/opencode"]
    ).discover()
    #expect(install.version == "1.17.0")
}

@Test func failsWithNotFoundWhenNothingResponds() async {
    await #expect(throws: OpenCodeDiscovery.DiscoveryError.notFound) {
        _ = try await OpenCodeDiscovery(
            runner: FakeCommandRunner(), shell: "/bin/zsh", fallbackPaths: []).discover()
    }
}

@Test func aVersionItCannotReadIsReportedAsSuch() async {
    let runner = FakeCommandRunner(responses: [
        "/opt/homebrew/bin/opencode --version": "não sou uma versão\n",
    ])
    await #expect(throws: OpenCodeDiscovery.DiscoveryError.unreadableVersion("não sou uma versão")) {
        _ = try await OpenCodeDiscovery(
            runner: runner, shell: "/bin/zsh",
            fallbackPaths: ["/opt/homebrew/bin/opencode"]).discover()
    }
}

@Test func theLaunchAsksForTheACPServerInTheRightDirectory() {
    let install = HarnessInstallation(executable: "/opt/homebrew/bin/opencode", version: "1.18.31")
    let launch = OpenCodeSession.launch(
        installation: install,
        workingDirectory: URL(fileURLWithPath: "/tmp/repo"))

    #expect(launch.arguments == ["acp", "--cwd", "/tmp/repo"])
    #expect(launch.workingDirectory.path == "/tmp/repo")
}
