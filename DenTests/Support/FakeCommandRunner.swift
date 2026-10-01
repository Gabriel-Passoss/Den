import Foundation
import HarnessCore

actor FakeCommandRunner: CommandRunner {
    nonisolated struct Call: Equatable {
        let executable: String
        let arguments: [String]
    }

    private(set) var calls: [Call] = []
    private var output: Result<String, HarnessFailure> = .success("")
    private var holding = false
    private var held: [CheckedContinuation<Void, Never>] = []

    func answer(with text: String) { output = .success(text) }

    func fail(_ failure: HarnessFailure) { output = .failure(failure) }

    func hold() { holding = true }

    func release() {
        holding = false
        held.forEach { $0.resume() }
        held = []
    }

    func run(_ executable: String, _ arguments: [String]) async throws -> String {
        calls.append(Call(executable: executable, arguments: arguments))
        if holding { await withCheckedContinuation { held.append($0) } }
        return try output.get()
    }
}
