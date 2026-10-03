import Darwin
import Foundation

nonisolated struct ProcessOutcome: Sendable, Equatable {
    var status: Int32
    var stdout: Data
    var stderr: Data

    var succeeded: Bool { status == 0 }

    var output: String {
        String(decoding: stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var errorLine: String {
        String(decoding: stderr, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty } ?? ""
    }
}

nonisolated enum TimedProcess {
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private var ended = false

        func append(_ chunk: Data) { lock.withLock { data.append(chunk) } }
        func end() { lock.withLock { ended = true } }
        var isEnded: Bool { lock.withLock { ended } }
        var collected: Data { lock.withLock { data } }
    }

    static func run(_ executable: String, _ arguments: [String],
                    in directory: URL? = nil,
                    environment: [String: String]? = nil,
                    timeout: Duration) async -> ProcessOutcome? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = directory }
        if let environment { process.environment = environment }
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let out = Collector()
        let err = Collector()
        drain(output, into: out)
        drain(errors, into: err)
        do {
            try process.run()
        } catch {
            stop(output, errors)
            return nil
        }

        let deadline = ContinuousClock.now + timeout
        while process.isRunning, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        guard !process.isRunning else {
            kill(process.processIdentifier, SIGKILL)
            stop(output, errors)
            return nil
        }
        let drainDeadline = ContinuousClock.now + .milliseconds(500)
        while !(out.isEnded && err.isEnded), ContinuousClock.now < drainDeadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        stop(output, errors)
        return ProcessOutcome(status: process.terminationStatus,
                              stdout: out.collected, stderr: err.collected)
    }

    private static func drain(_ pipe: Pipe, into collector: Collector) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                collector.end()
            } else {
                collector.append(chunk)
            }
        }
    }

    private static func stop(_ pipes: Pipe...) {
        for pipe in pipes { pipe.fileHandleForReading.readabilityHandler = nil }
    }
}
