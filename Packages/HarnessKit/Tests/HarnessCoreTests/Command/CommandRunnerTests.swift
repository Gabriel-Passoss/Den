import Testing
import Foundation
@testable import HarnessCore
import HarnessTestSupport

@Test func drainsStderrConcurrentlySoItCannotDeadlock() async throws {
    let runner = SystemCommandRunner()
    let output = try await withTimeout(seconds: 5) {

        try await runner.run("/bin/sh", ["-c", "yes x | head -c 200000 >&2; echo done"])
    }
    #expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == "done")
}

@Test func manyShortRunsAtOnceAllComeBack() async throws {
    let runner = SystemCommandRunner()
    let outputs = try await withTimeout(seconds: 30) {
        try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<100 {
                group.addTask { try await runner.run("/bin/echo", ["ok"]) }
            }
            return try await group.reduce(into: [String]()) { $0.append($1) }
        }
    }
    #expect(outputs.count == 100,
            "each run completes on its exit and both pipe ends, in any order, and returns exactly once")
    #expect(Set(outputs) == ["ok\n"])
}

@Test func aFailingRunReportsItsStatusAndStderr() async throws {
    let runner = SystemCommandRunner()
    await #expect(throws: CommandFailure(exitCode: 4, stderr: "nope\n")) {
        try await withTimeout(seconds: 5) {
            try await runner.run("/bin/sh", ["-c", "echo nope >&2; exit 4"])
        }
    }
}
