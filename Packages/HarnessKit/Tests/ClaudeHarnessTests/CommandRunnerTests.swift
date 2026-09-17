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

private struct TimedOut: Error {}

/// Corre `operation` competindo com um sleep; se o sleep vencer, falha em vez
/// de travar a suíte inteira. Não usa `TaskGroup` de propósito: sair do escopo
/// de um `TaskGroup` espera implicitamente todas as child tasks terminarem, o
/// que inclui a travada — anulando o timeout. Uma continuation avulsa,
/// resolvida uma única vez por quem chegar primeiro, não tem essa espera.
private func withTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let once = OnceContinuation(continuation)
        Task {
            do {
                let value = try await operation()
                await once.resume(returning: value)
            } catch {
                await once.resume(throwing: error)
            }
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            await once.resume(throwing: TimedOut())
        }
    }
}

private actor OnceContinuation<T: Sendable> {
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        continuation?.resume(returning: value)
        continuation = nil
    }

    func resume(throwing error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
