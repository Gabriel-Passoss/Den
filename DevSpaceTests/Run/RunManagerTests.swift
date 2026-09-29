import Testing
import Foundation
import Darwin
@testable import DevSpace

private let project = FileManager.default.temporaryDirectory

nonisolated private func shellOutput() -> Data { Data("__DEVSPACE_ENV__\nPATH=/bin\u{0}".utf8) }

private func makeManager(_ launcher: FakeLauncher,
                         probe: @escaping ShellEnvironment.Probe = { _, _, _ in shellOutput() }) -> RunManager {
    RunManager(launcher: launcher,
               environment: ShellEnvironment(shell: "/bin/zsh", base: ["PATH": "/usr/bin"], probe: probe),
               stopGrace: .seconds(1), logInterval: .zero)
}

private func command(_ name: String = "API", _ command: String = "npm run dev",
                     directory: String = "", environment: [EnvVar] = []) -> RunConfiguration {
    RunConfiguration(name: name, kind: .command(CommandSpec(
        command: command, workingDirectory: directory, environment: environment)))
}

@Test func startLaunchesTheCommandThroughTheShell() async throws {
    let launcher = FakeLauncher()
    let manager = makeManager(launcher)
    let api = command(environment: [EnvVar(key: "PORT", value: "3000")])

    await manager.start(api, in: project)

    let request = try #require(launcher.requests.first)
    #expect(request.shell == "/bin/zsh")
    #expect(request.command == "npm run dev")
    #expect(request.directory == project)
    #expect(request.environment["PATH"] == "/bin")
    #expect(request.environment["TERM"] == "xterm-256color")
    #expect(request.environment["COLORTERM"] == "truecolor")
    #expect(request.environment["PORT"] == "3000")
    #expect(manager.instance(for: api.id)?.state == .running(pid: 100))
    #expect(manager.hasActiveProcesses)
}

@Test func configurationVariablesWinAndBlankKeysAreSkipped() async throws {
    let launcher = FakeLauncher()
    let manager = makeManager(launcher)
    await manager.start(command(environment: [EnvVar(key: "TERM", value: "dumb"),
                                              EnvVar(key: " ", value: "x"),
                                              EnvVar(key: "A=B", value: "y")]), in: project)

    let environment = try #require(launcher.requests.first?.environment)
    #expect(environment["TERM"] == "dumb")
    #expect(environment[" "] == nil)
    #expect(environment[""] == nil)
    #expect(environment["A=B"] == nil)
}

@Test func outputReachesTheInstanceLog() async throws {
    let launcher = FakeLauncher()
    let manager = makeManager(launcher)
    let api = command()
    await manager.start(api, in: project)
    let instance = try #require(manager.instance(for: api.id))

    launcher.processes[0].emit("hello \u{1B}[32mworld\u{1B}[0m\n")
    await waitUntil { instance.log.plainText == "hello world\n" }

    #expect(instance.log.plainText == "hello world\n")
}

@Test func anExitOnItsOwnIsRecorded() async throws {
    let launcher = FakeLauncher()
    let manager = makeManager(launcher)
    let api = command()
    await manager.start(api, in: project)
    let instance = try #require(manager.instance(for: api.id))

    launcher.processes[0].exit(.code(1))
    await waitUntil { instance.state == .exited(.code(1)) }

    #expect(instance.state == .exited(.code(1)))
    #expect(!manager.hasActiveProcesses)
}

@Test func stopMarksTheInstanceStopped() async throws {
    let launcher = FakeLauncher()
    let manager = makeManager(launcher)
    let api = command()
    await manager.start(api, in: project)
    let instance = try #require(manager.instance(for: api.id))

    await manager.stop(api.id)
    await waitUntil { instance.state == .stopped }

    #expect(instance.state == .stopped)
    #expect(launcher.processes[0].terminations == 1)
    #expect(!manager.hasActiveProcesses)
}

@Test func startingARunningConfigurationRestartsIt() async throws {
    let launcher = FakeLauncher()
    let manager = makeManager(launcher)
    let api = command()
    await manager.start(api, in: project)
    let instance = try #require(manager.instance(for: api.id))
    let first = launcher.processes[0]
    first.emit("old\n")
    await waitUntil { instance.log.plainText.contains("old") }

    await manager.start(api, in: project)

    #expect(first.terminations == 1)
    #expect(launcher.processes.count == 2)
    #expect(instance.state == .running(pid: 101))
    #expect(!instance.log.plainText.contains("old"))

    first.emit("late\n")
    first.exit(.code(0))
    launcher.processes[1].emit("fresh\n")
    await waitUntil { instance.log.plainText.contains("fresh") }

    #expect(!instance.log.plainText.contains("late"))
    #expect(instance.state == .running(pid: 101))
    #expect(manager.instance(for: api.id) === instance)
    #expect(manager.hasActiveProcesses)
}

@Test func aMissingDirectoryFailsWithoutLaunching() async throws {
    let launcher = FakeLauncher()
    let manager = makeManager(launcher)
    let api = command(directory: "missing-\(UUID().uuidString)")

    await manager.start(api, in: project)

    let instance = try #require(manager.instance(for: api.id))
    guard case .failed(let message) = instance.state else {
        Issue.record("expected a failure, got \(instance.state)")
        return
    }
    #expect(message.contains("não existe"))
    #expect(instance.log.plainText.contains(message))
    #expect(launcher.requests.isEmpty)
}

@Test func aLaunchErrorBecomesAFailure() async throws {
    let launcher = FakeLauncher()
    launcher.fail(with: .spawnFailed(ENOENT))
    let manager = makeManager(launcher)
    let api = command()

    await manager.start(api, in: project)

    guard case .failed? = manager.instance(for: api.id)?.state else {
        Issue.record("expected a failure")
        return
    }
    #expect(!manager.hasActiveProcesses)
}

@Test func theShellFallbackWarningOpensTheLog() async throws {
    let launcher = FakeLauncher()
    let manager = makeManager(launcher) { _, _, _ in nil }
    let api = command()

    await manager.start(api, in: project)

    let instance = try #require(manager.instance(for: api.id))
    #expect(instance.log.lines.first?.text == ShellEnvironment.fallbackWarning)
}

@Test func stoppingWhileTheEnvironmentResolvesCancelsTheStart() async throws {
    let launcher = FakeLauncher()
    let manager = makeManager(launcher) { _, _, _ in
        try? await Task.sleep(for: .milliseconds(300))
        return shellOutput()
    }
    let api = command()

    let start = Task { await manager.start(api, in: project) }
    await waitUntil { manager.instance(for: api.id)?.state == .starting }
    await manager.stop(api.id)
    await start.value

    #expect(manager.instance(for: api.id)?.state == .stopped)
    #expect(launcher.requests.isEmpty)
}

@Test func stopAllTerminatesEverything() async throws {
    let launcher = FakeLauncher()
    let manager = makeManager(launcher)
    await manager.start(command("API"), in: project)
    await manager.start(command("Web"), in: project)

    await manager.stopAll(grace: .seconds(1))
    await waitUntil { !manager.hasActiveProcesses }

    #expect(launcher.processes.map(\.terminations) == [1, 1])
    #expect(!manager.hasActiveProcesses)
}

@Test func forgetDropsAnIdleInstanceOnly() async throws {
    let launcher = FakeLauncher()
    let manager = makeManager(launcher)
    let api = command()
    await manager.start(api, in: project)

    manager.forget(api.id)
    #expect(manager.instance(for: api.id) != nil)

    await manager.stop(api.id)
    await waitUntil { manager.instance(for: api.id)?.state == .stopped }
    manager.forget(api.id)
    #expect(manager.instance(for: api.id) == nil)
}

@Test func theRealPipelineRunsAColoredCommandEndToEnd() async throws {
    let manager = RunManager(environment: ShellEnvironment(shell: "/bin/sh"), logInterval: .zero)
    let echo = command("Echo", "printf '\\033[32mok\\033[0m\\n'; exit 4")

    await manager.start(echo, in: project)
    let instance = try #require(manager.instance(for: echo.id))
    await waitUntil { instance.state == .exited(.code(4)) }

    #expect(instance.state == .exited(.code(4)))
    #expect(instance.log.lines.first?.text == "ok")
    #expect(instance.log.lines.first?.spans.first?.style.foreground == .palette(2))
}

@Test func isActiveFollowsTheConfigurationsRun() async throws {
    let launcher = FakeLauncher()
    let manager = makeManager(launcher)
    let api = command()
    #expect(!manager.isActive(api.id))

    await manager.start(api, in: project)
    #expect(manager.isActive(api.id))

    await manager.stop(api.id)
    await waitUntil { !manager.isActive(api.id) }
    #expect(!manager.isActive(api.id))
}

private func settle() async {
    try? await Task.sleep(for: .milliseconds(100))
}

@MainActor private final class Flag {
    var raised = false
}

@Test func stopStaysStoppingUntilTheWholeGroupIsGone() async throws {
    let launcher = FakeLauncher()
    let manager = makeManager(launcher)
    let api = command()
    await manager.start(api, in: project)
    let instance = try #require(manager.instance(for: api.id))
    let process = launcher.processes[0]
    process.holdTermination()

    let stopping = Task { await manager.stop(api.id) }
    await waitUntil { process.terminations == 1 }
    await settle()
    #expect(instance.state == .stopping)
    #expect(manager.hasActiveProcesses)

    process.releaseTermination()
    await stopping.value
    #expect(instance.state == .stopped)
    #expect(!manager.hasActiveProcesses)
}

@Test func aRestartDuringAStopWaitsForIt() async throws {
    let launcher = FakeLauncher()
    let manager = makeManager(launcher)
    let api = command()
    await manager.start(api, in: project)
    let instance = try #require(manager.instance(for: api.id))
    let first = launcher.processes[0]
    first.holdTermination()

    let stopping = Task { await manager.stop(api.id) }
    await waitUntil { first.terminations == 1 }
    await settle()
    let restarting = Task { await manager.start(api, in: project) }
    await settle()
    #expect(launcher.processes.count == 1)

    first.releaseTermination()
    await stopping.value
    await restarting.value
    #expect(launcher.processes.count == 2)
    #expect(instance.state == .running(pid: 101))
}

@Test func stopAllWaitsForStopsAlreadyUnderWay() async throws {
    let launcher = FakeLauncher()
    let manager = makeManager(launcher)
    let api = command()
    await manager.start(api, in: project)
    let process = launcher.processes[0]
    process.holdTermination()

    let stopping = Task { await manager.stop(api.id) }
    await waitUntil { process.terminations == 1 }
    await settle()
    let done = Flag()
    let quitting = Task {
        await manager.stopAll(grace: .seconds(1))
        done.raised = true
    }
    await settle()
    #expect(!done.raised)

    process.releaseTermination()
    await stopping.value
    await quitting.value
    #expect(done.raised)
}
