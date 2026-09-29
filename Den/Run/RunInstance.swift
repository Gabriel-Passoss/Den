import Foundation
import Observation

@MainActor
@Observable
final class RunInstance {
    let configurationID: UUID
    private(set) var state: RunState = .starting
    private(set) var startedAt = Date()

    @ObservationIgnored private(set) var generation = 0
    @ObservationIgnored private(set) var log: LogBuffer
    @ObservationIgnored private var observers: [UUID: ([LogChange]) -> Void] = [:]

    init(configurationID: UUID, logCapacity: Int = 20_000) {
        self.configurationID = configurationID
        self.log = LogBuffer(capacity: logCapacity)
    }

    var isActive: Bool { state.isActive }

    func begin() -> Int {
        generation += 1
        state = .starting
        startedAt = Date()
        publish(log.clear())
        return generation
    }

    func markRunning(pid: Int32) { state = .running(pid: pid) }

    func markStopping() { state = .stopping }

    func markStopped() {
        generation += 1
        state = .stopped
    }

    func fail(_ message: String) {
        appendNotice(message)
        state = .failed(message)
    }

    @discardableResult
    func finish(_ status: ProcessExit, generation: Int) -> Bool {
        guard generation == self.generation else { return false }
        if state != .stopping, state != .stopped { state = .exited(status) }
        return true
    }

    func settleStop(generation: Int) {
        guard generation == self.generation, state == .stopping else { return }
        state = .stopped
    }

    func receive(_ events: [ANSIParser.Event], generation: Int) {
        guard generation == self.generation else { return }
        publish(log.apply(events))
    }

    func appendNotice(_ text: String) {
        var events: [ANSIParser.Event] = []
        if let last = log.lines.last, !last.spans.isEmpty { events.append(.newline) }
        events += [.text(text, .notice), .newline]
        publish(log.apply(events))
    }

    func clearLog() { publish(log.clear()) }

    func observeLog(_ handler: @escaping ([LogChange]) -> Void) -> UUID {
        let token = UUID()
        observers[token] = handler
        return token
    }

    func stopObserving(_ token: UUID) { observers[token] = nil }

    private func publish(_ changes: [LogChange]) {
        guard !changes.isEmpty else { return }
        for observer in observers.values { observer(changes) }
    }
}
