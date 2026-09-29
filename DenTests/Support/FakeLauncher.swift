import Foundation
import Darwin
@testable import Den

nonisolated final class FakeProcess: RunningProcess, @unchecked Sendable {
    let pid: Int32
    private let onOutput: @Sendable (Data) -> Void
    private let onExit: @Sendable (ProcessExit) -> Void
    private let lock = NSLock()
    private var terminateCalls = 0
    private var holding = false
    private var waiter: CheckedContinuation<Void, Never>?

    init(pid: Int32, onOutput: @escaping @Sendable (Data) -> Void,
         onExit: @escaping @Sendable (ProcessExit) -> Void) {
        self.pid = pid
        self.onOutput = onOutput
        self.onExit = onExit
    }

    var terminations: Int { lock.withLock { terminateCalls } }

    func emit(_ text: String) { onOutput(Data(text.utf8)) }
    func exit(_ status: ProcessExit) { onExit(status) }

    func holdTermination() { lock.withLock { holding = true } }

    func releaseTermination() {
        let pending: CheckedContinuation<Void, Never>? = lock.withLock {
            holding = false
            defer { waiter = nil }
            return waiter
        }
        pending?.resume()
    }

    func terminate(grace: Duration) async {
        lock.withLock { terminateCalls += 1 }
        onExit(.signal(SIGTERM))
        await withCheckedContinuation { continuation in
            let resumeNow: Bool = lock.withLock {
                guard holding else { return true }
                waiter = continuation
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }
}

nonisolated final class FakeLauncher: ProcessLaunching, @unchecked Sendable {
    private let lock = NSLock()
    private var launched: [(LaunchRequest, FakeProcess)] = []
    private var nextFailure: LaunchError?

    func fail(with error: LaunchError) { lock.withLock { nextFailure = error } }

    var requests: [LaunchRequest] { lock.withLock { launched.map(\.0) } }
    var processes: [FakeProcess] { lock.withLock { launched.map(\.1) } }

    func launch(_ request: LaunchRequest,
                onOutput: @escaping @Sendable (Data) -> Void,
                onExit: @escaping @Sendable (ProcessExit) -> Void) throws -> any RunningProcess {
        try lock.withLock {
            if let nextFailure {
                self.nextFailure = nil
                throw nextFailure
            }
            let process = FakeProcess(pid: Int32(100 + launched.count),
                                      onOutput: onOutput, onExit: onExit)
            launched.append((request, process))
            return process
        }
    }
}
