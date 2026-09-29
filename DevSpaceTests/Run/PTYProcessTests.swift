import Testing
import Foundation
import Darwin
@testable import DevSpace

nonisolated private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var status: ProcessExit?
    private var exits = 0

    func append(_ chunk: Data) { lock.withLock { data.append(chunk) } }
    func finish(_ value: ProcessExit) { lock.withLock { status = value; exits += 1 } }
    var text: String {
        lock.withLock { String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r", with: "") }
    }
    var exitStatus: ProcessExit? { lock.withLock { status } }
    var exitCount: Int { lock.withLock { exits } }
}

private func launch(_ command: String,
                    in directory: URL = FileManager.default.temporaryDirectory,
                    environment: [String: String] = ["PATH": "/usr/bin:/bin"],
                    shell: String = "/bin/sh") throws -> (PTYProcess, Recorder) {
    let recorder = Recorder()
    let process = try PTYProcess.spawn(
        LaunchRequest(shell: shell, command: command, directory: directory, environment: environment),
        onOutput: { recorder.append($0) },
        onExit: { recorder.finish($0) })
    return (process, recorder)
}

@Test func outputArrivesThroughATerminal() async throws {
    let (_, recorder) = try launch("test -t 1 && echo IS_TTY; printf 'a\\nb\\n'")
    await waitUntil { recorder.exitStatus != nil }
    #expect(recorder.exitStatus == .code(0))
    #expect(recorder.text == "IS_TTY\na\nb\n")
}

@Test func anInstantExitStillDeliversEverything() async throws {
    let (_, recorder) = try launch("seq 1 2000")
    await waitUntil { recorder.exitStatus != nil }
    let lines = recorder.text.split(separator: "\n")
    #expect(lines.count == 2000)
    #expect(lines.last == "2000")
    #expect(recorder.exitCount == 1)
}

@Test func theExitCodeIsReported() async throws {
    let (_, recorder) = try launch("exit 3")
    await waitUntil { recorder.exitStatus != nil }
    #expect(recorder.exitStatus == .code(3))
}

@Test func aSignalDeathIsReported() async throws {
    let (_, recorder) = try launch("kill -9 $$")
    await waitUntil { recorder.exitStatus != nil }
    #expect(recorder.exitStatus == .signal(SIGKILL))
}

@Test func theWorkingDirectoryAndEnvironmentAreApplied() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "DevSpaceTests-" + UUID().uuidString)
        .appending(path: "folder with space ç")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

    let (_, recorder) = try launch("pwd; echo \"$GREETING\"", in: directory,
                                   environment: ["PATH": "/usr/bin:/bin", "GREETING": "héllo=world"])
    await waitUntil { recorder.exitStatus != nil }
    let lines = recorder.text.split(separator: "\n").map(String.init)
    #expect(lines.first?.hasSuffix("/folder with space ç") == true)
    #expect(lines.last == "héllo=world")
}

@Test func aMissingShellFailsToSpawn() {
    #expect(throws: LaunchError.self) {
        _ = try launch("true", shell: "/nonexistent/shell")
    }
}

@Test func terminateTakesDownTheWholeGroup() async throws {
    let (process, recorder) = try launch("sleep 60 & echo $!; wait")
    await waitUntil { recorder.text.contains("\n") }
    let child = try #require(Int32(recorder.text.trimmingCharacters(in: .whitespacesAndNewlines)))
    #expect(kill(child, 0) == 0)

    await process.terminate(grace: .seconds(5))
    await waitUntil { kill(child, 0) != 0 }

    #expect(kill(child, 0) != 0)
    #expect(recorder.exitStatus == .signal(SIGTERM))
}

@Test func aProcessIgnoringTermIsKilled() async throws {
    let (process, recorder) = try launch("trap '' TERM; echo ready; while :; do sleep 1; done")
    await waitUntil { recorder.text.contains("ready") }

    await process.terminate(grace: .milliseconds(300))
    await waitUntil { recorder.exitStatus != nil }

    #expect(recorder.exitStatus == .signal(SIGKILL))
}

@Test func terminateAfterExitDoesNothing() async throws {
    let (process, recorder) = try launch("true")
    await waitUntil { recorder.exitStatus != nil }
    await process.terminate(grace: .seconds(1))
    #expect(recorder.exitCount == 1)
}

@Test func stdinStaysOpenWithoutBeingATerminal() async throws {
    let probe = #"use IO::Select; print IO::Select->new(\*STDIN)->can_read(0) ? "STDIN_AT_END\n" : "STDIN_OPEN\n""#
    let (_, recorder) = try launch("test -t 0 || echo NOT_A_TTY; /usr/bin/perl -e '\(probe)'")
    await waitUntil { recorder.exitStatus != nil }
    #expect(recorder.text == "NOT_A_TTY\nSTDIN_OPEN\n")
}

@Test func commandsRunBehindTheGuard() {
    let request = LaunchRequest(shell: "/opt/homebrew/bin/fish", command: "npm start",
                                directory: URL(fileURLWithPath: "/tmp"), environment: [:])
    #expect(PTYProcess.arguments(for: request)
            == ["/bin/sh", "-c", PTYProcess.guardScript, "/opt/homebrew/bin/fish", "npm start"])
}

@Test func aBackgroundChildIsCleanedUpAfterTheShellExits() async throws {
    let (_, recorder) = try launch("sleep 60 & echo $!")
    await waitUntil { recorder.exitStatus != nil }
    let sleeper = try #require(Int32(recorder.text.trimmingCharacters(in: .whitespacesAndNewlines)))
    defer { kill(sleeper, SIGKILL) }

    await waitUntil { kill(sleeper, 0) != 0 }

    #expect(kill(sleeper, 0) != 0)
}

@Test func theGroupDiesWhenTheParentDies() async throws {
    let input = Pipe()
    let output = Pipe()
    let parent = Process()
    parent.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
    parent.arguments = ["-MPOSIX", "-e", "exit 0 if fork; POSIX::setsid(); exec @ARGV or die $!"]
        + PTYProcess.arguments(for: LaunchRequest(
            shell: "/bin/sh", command: "sleep 60 & echo $!; wait",
            directory: FileManager.default.temporaryDirectory, environment: [:]))
    parent.standardInput = input
    parent.standardOutput = output
    try parent.run()
    let line = String(decoding: output.fileHandleForReading.availableData, as: UTF8.self)
    let sleeper = try #require(Int32(line.trimmingCharacters(in: .whitespacesAndNewlines)))
    defer { kill(sleeper, SIGKILL) }
    #expect(kill(sleeper, 0) == 0)

    try input.fileHandleForWriting.close()
    await waitUntil { kill(sleeper, 0) != 0 }

    #expect(kill(sleeper, 0) != 0)
}

@Test func launchErrorsExplainThemselves() {
    #expect(LaunchError.spawnFailed(ENOENT).message
            == "Não consegui iniciar o processo: No such file or directory")
    #expect(LaunchError.terminalUnavailable(EMFILE).message
            == "Não consegui abrir um terminal para o processo: Too many open files")
}

@Test func terminateWaitsForTheWholeGroup() async throws {
    let (process, recorder) = try launch(
        "sh -c 'trap \"sleep 1; exit 0\" TERM; while :; do sleep 0.1; done' & echo $!; wait")
    await waitUntil { recorder.text.contains("\n") }
    let lingering = try #require(Int32(recorder.text.trimmingCharacters(in: .whitespacesAndNewlines)))
    defer { kill(lingering, SIGKILL) }

    await process.terminate(grace: .seconds(5))

    #expect(kill(lingering, 0) != 0)
}
