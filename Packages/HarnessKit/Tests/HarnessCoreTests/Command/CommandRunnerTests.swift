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
