import Testing
import Foundation
@testable import ClaudeHarness

/// Regressão para o Finding 1: `SystemCommandRunner` tem que drenar stdout e
/// stderr em paralelo. Se voltar a ler só um dos dois, um filho que escreve
/// mais que o teto do pipe do SO (~64 KiB) no outro trava para sempre — e sem
/// isso, essa suíte trava com ele em vez de falhar.
@Test func drenaStderrConcorrentementeParaNaoTravar() async throws {
    let runner = SystemCommandRunner()
    let output = try await withTimeout(seconds: 5) {
        // Escreve bem mais que 64 KiB em stderr antes de sair.
        try await runner.run("/bin/sh", ["-c", "yes x | head -c 200000 >&2; echo done"])
    }
    #expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == "done")
}
