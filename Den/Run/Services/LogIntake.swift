import Foundation

nonisolated final class LogIntake: @unchecked Sendable {
    private let lock = NSLock()
    private var parser = ANSIParser()
    private var pending: [ANSIParser.Event] = []
    private var flushScheduled = false
    private let interval: Duration
    private let deliver: @MainActor @Sendable ([ANSIParser.Event]) -> Void

    init(interval: Duration = .milliseconds(60),
         deliver: @escaping @MainActor @Sendable ([ANSIParser.Event]) -> Void) {
        self.interval = interval
        self.deliver = deliver
    }

    func receive(_ data: Data) {
        let schedule: Bool = lock.withLock {
            pending += parser.feed(data)
            guard !flushScheduled, !pending.isEmpty else { return false }
            flushScheduled = true
            return true
        }
        guard schedule else { return }
        let interval = self.interval
        Task { @MainActor [self] in
            try? await Task.sleep(for: interval)
            drain()
        }
    }

    func finish(then completion: @escaping @MainActor @Sendable () -> Void) {
        lock.withLock { pending += parser.finish() }
        Task { @MainActor [self] in
            drain()
            completion()
        }
    }

    @MainActor
    private func drain() {
        let events: [ANSIParser.Event] = lock.withLock {
            let taken = pending
            pending = []
            flushScheduled = false
            return taken
        }
        if !events.isEmpty { deliver(events) }
    }
}
