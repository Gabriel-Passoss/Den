import Foundation

public protocol CommandRunner: Sendable {
    func run(_ executable: String, _ arguments: [String]) async throws -> String
}

public struct CommandFailure: Error, Equatable {
    public let exitCode: Int32
    public let stderr: String

    public init(exitCode: Int32, stderr: String) {
        self.exitCode = exitCode
        self.stderr = stderr
    }
}

public struct SystemCommandRunner: CommandRunner {
    public init() {}

    public func run(_ executable: String, _ arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Nothing here blocks a thread: output arrives through readability
        // handlers and the exit through the termination handler. Blocking reads
        // plus `waitUntilExit` could starve the queue that reports the exit and
        // hang with the process long gone.
        let run = RunCollector()
        process.terminationHandler = { run.exited(with: $0.terminationStatus) }
        try process.run()
        run.collect(stdoutPipe.fileHandleForReading, as: .output)
        run.collect(stderrPipe.fileHandleForReading, as: .errorOutput)

        let (status, outData, errData) = await run.result()
        guard status == 0 else {
            throw CommandFailure(exitCode: status, stderr: String(decoding: errData, as: UTF8.self))
        }
        return String(decoding: outData, as: UTF8.self)
    }
}

/// Gathers what a run produces and hands it over once the process has exited
/// and both of its pipes have closed.
private final class RunCollector: @unchecked Sendable {
    enum Stream: Sendable { case output, errorOutput }

    private let lock = NSLock()
    private var output = Data()
    private var errorOutput = Data()
    private var status: Int32 = 0
    /// The exit, and the end of each of the two pipes.
    private var outstanding = 3
    private var waiting: CheckedContinuation<(Int32, Data, Data), Never>?

    func exited(with status: Int32) {
        finishOne { self.status = status }
    }

    func collect(_ handle: FileHandle, as stream: Stream) {
        handle.readabilityHandler = { [self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                finishOne {}
                return
            }
            lock.withLock {
                switch stream {
                case .output: output.append(chunk)
                case .errorOutput: errorOutput.append(chunk)
                }
            }
        }
    }

    func result() async -> (Int32, Data, Data) {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if outstanding == 0 {
                    continuation.resume(returning: (status, output, errorOutput))
                } else {
                    waiting = continuation
                }
            }
        }
    }

    private func finishOne(_ record: () -> Void) {
        lock.withLock {
            record()
            outstanding -= 1
            guard outstanding == 0, let waiting else { return }
            self.waiting = nil
            waiting.resume(returning: (status, output, errorOutput))
        }
    }
}
