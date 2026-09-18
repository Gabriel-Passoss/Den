import Testing
@testable import HarnessProbeArguments

private func probe(directories: Set<String> = [], files: Set<String> = []) -> FileSystemProbe {
    FileSystemProbe(
        exists: { directories.contains($0) || files.contains($0) },
        isDirectory: { directories.contains($0) }
    )
}

@Suite("preflightRecord")
struct RecordPreflightTests {
    @Test("an existing --cwd and an unused --out pass")
    func happyPath() {
        let problem = preflightRecord(
            RecordArguments(prompt: "oi", cwd: "/tmp/probe-scratch", outputPath: "/tmp/novo.ndjson"),
            on: probe(directories: ["/tmp/probe-scratch"])
        )
        #expect(problem == nil)
    }

    @Test("a missing --out really is optional")
    func withoutOut() {
        let problem = preflightRecord(
            RecordArguments(prompt: "oi", cwd: "/tmp/probe-scratch"),
            on: probe(directories: ["/tmp/probe-scratch"])
        )
        #expect(problem == nil)
    }

    @Test("a nonexistent --cwd is refused")
    func nonexistentCwd() {
        let problem = preflightRecord(
            RecordArguments(prompt: "oi", cwd: "/tmp/probe-scratchh"),
            on: probe(directories: ["/tmp/probe-scratch"])
        )
        #expect(problem == .cwdNotFound("/tmp/probe-scratchh"))
        #expect(problem?.exitCode == 66)
    }

    @Test("a --cwd pointing at a file is refused")
    func cwdPointingAtAFile() {
        let problem = preflightRecord(
            RecordArguments(prompt: "oi", cwd: "/tmp/arquivo.txt"),
            on: probe(files: ["/tmp/arquivo.txt"])
        )
        #expect(problem == .cwdNotADirectory("/tmp/arquivo.txt"))
    }

    @Test("an existing --out is never overwritten")
    func existingOut() {
        let fixture = "Tests/ClaudeHarnessTests/Fixtures/hello.ndjson"
        let problem = preflightRecord(
            RecordArguments(prompt: "oi", cwd: "/tmp/probe-scratch", outputPath: fixture),
            on: probe(directories: ["/tmp/probe-scratch"], files: [fixture])
        )
        #expect(problem == .outputAlreadyExists(fixture))
        #expect(problem?.exitCode == 73)
    }

    @Test("with a bad --cwd and an existing --out, the reported error is the --cwd one")
    func cwdIsCheckedBeforeOut() {
        let fixture = "Tests/ClaudeHarnessTests/Fixtures/hello.ndjson"
        let problem = preflightRecord(
            RecordArguments(prompt: "oi", cwd: "/tmp/probe-scratchh", outputPath: fixture),
            on: probe(directories: ["/tmp/probe-scratch"], files: [fixture])
        )
        #expect(problem == .cwdNotFound("/tmp/probe-scratchh"))
    }

    @Test("every message names the offending path")
    func everyMessageNamesTheOffendingPath() {
        #expect(RecordPreflightError.cwdNotFound("/x/y").message.contains("/x/y"))
        #expect(RecordPreflightError.cwdNotADirectory("/x/y").message.contains("/x/y"))
        #expect(RecordPreflightError.outputAlreadyExists("/x/y").message.contains("/x/y"))
    }
}
