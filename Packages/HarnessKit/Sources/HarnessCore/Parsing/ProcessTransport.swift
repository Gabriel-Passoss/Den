import Darwin
import Foundation
import Synchronization

final class StreamIO: @unchecked Sendable {
    private let lock = NSLock()
    private let outputHandle: FileHandle
    private let errorHandle: FileHandle
    private var framer: NDJSONFramer
    private var errorBytes = Data()
    private var hasFramingFailed = false
    private var hasFinished = false

    init(outputHandle: FileHandle, errorHandle: FileHandle, framingLimit: Int) {
        self.outputHandle = outputHandle
        self.errorHandle = errorHandle
        self.framer = NDJSONFramer(limit: framingLimit)
    }

    var collectedStandardError: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: errorBytes, as: UTF8.self)
    }

    func startReading(
        onLines: @escaping @Sendable ([Data]) -> Void,
        onFramingFailure: @escaping @Sendable (any Error) -> Void
    ) {
        outputHandle.readabilityHandler = { [self] handle in
            lock.lock()
            defer { lock.unlock() }
            guard !hasFinished, !hasFramingFailed else {
                handle.readabilityHandler = nil
                return
            }

            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            do {
                onLines(try framer.push(chunk))
            } catch {
                hasFramingFailed = true
                onFramingFailure(error)
            }
        }

        errorHandle.readabilityHandler = { [self] handle in
            lock.lock()
            defer { lock.unlock() }
            guard !hasFinished else {
                handle.readabilityHandler = nil
                return
            }
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            errorBytes.append(chunk)
        }
    }

    func finishReading() throws -> [Data] {
        outputHandle.readabilityHandler = nil
        errorHandle.readabilityHandler = nil

        lock.lock()
        defer { lock.unlock() }
        guard !hasFinished else { return [] }
        hasFinished = true

        errorBytes.append(Self.readPending(errorHandle))
        guard !hasFramingFailed else { return [] }
        do {
            return try framer.push(Self.readPending(outputHandle))
        } catch {
            hasFramingFailed = true
            throw error
        }
    }

    static let sweepReadSize = 64 * 1024

    static let sweepByteLimit = 2 * sweepReadSize

    static let sweepBudget = Duration.milliseconds(100)

    static func readPending(_ handle: FileHandle) -> Data {
        let descriptor = handle.fileDescriptor
        let deadline = ContinuousClock.now + sweepBudget
        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: sweepReadSize)
        while pending.count < sweepByteLimit, ContinuousClock.now < deadline {
            var poller = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&poller, 1, 0) > 0 else { break }
            let count = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { break }
            pending.append(contentsOf: buffer[0..<count])
        }
        return pending
    }
}

public actor ProcessTransport {
    public struct Launch: Sendable {
        public var executable: String
        public var arguments: [String]
        public var workingDirectory: URL
        public var environment: [String: String]

        public init(
            executable: String,
            arguments: [String],
            workingDirectory: URL,
            environment: [String: String] = ProcessInfo.processInfo.environment
        ) {
            self.executable = executable
            self.arguments = arguments
            self.workingDirectory = workingDirectory
            self.environment = environment
        }
    }

    public enum TransportError: Error, Equatable {

        case notRunning

        case alreadyStarted
    }

    /// The CLI ended without being asked to: a failing exit status, or a
    /// signal it did not get from `terminate()`. It is how the stream ends
    /// then, so the reason reaches whoever reads it instead of looking like a
    /// clean end of output.
    public struct ExitFailure: Error, Equatable, CustomStringConvertible {
        public let status: Int32
        public let standardError: String
        public let signaled: Bool

        public init(status: Int32, standardError: String, signaled: Bool = false) {
            self.status = status
            self.standardError = standardError
            self.signaled = signaled
        }

        public var description: String {
            let detail = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            let head = signaled
                ? "o CLI foi encerrado pelo sinal \(status)"
                : "o CLI saiu com código \(status)"
            return detail.isEmpty ? head : head + ": " + String(detail.suffix(500))
        }
    }

    private let framingLimit: Int
    private let terminationGracePeriod: Duration
    private let killGracePeriod: Duration
    private var process: Process?
    private var standardInput: FileHandle?
    private var io: StreamIO?

    private let syncStandardInput = Mutex<FileHandle?>(nil)

    private let stopRequested = Mutex(false)

    public init(
        framingLimit: Int = 8 * 1024 * 1024,
        terminationGracePeriod: Duration = .seconds(5),
        killGracePeriod: Duration = .seconds(3)
    ) {
        self.framingLimit = framingLimit
        self.terminationGracePeriod = terminationGracePeriod
        self.killGracePeriod = killGracePeriod
    }

    public var standardError: String { io?.collectedStandardError ?? "" }

    public var terminationStatus: Int32? {
        guard let process, !process.isRunning else { return nil }
        return process.terminationStatus
    }

    public func start(_ launch: Launch) throws -> AsyncThrowingStream<Data, Error> {
        guard self.process == nil else { throw TransportError.alreadyStarted }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch.executable)
        process.arguments = launch.arguments
        process.currentDirectoryURL = launch.workingDirectory
        process.environment = launch.environment

        let input = Pipe(), output = Pipe(), errorOutput = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errorOutput

        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        let io = StreamIO(
            outputHandle: output.fileHandleForReading,
            errorHandle: errorOutput.fileHandleForReading,
            framingLimit: framingLimit
        )

        let stream = AsyncThrowingStream<Data, Error> { continuation in
            io.startReading(
                onLines: { lines in
                    for line in lines { continuation.yield(line) }
                },
                onFramingFailure: { error in
                    continuation.finish(throwing: error)

                    Task { await self.terminate() }
                }
            )

            process.terminationHandler = { ended in
                do {
                    for line in try io.finishReading() { continuation.yield(line) }
                    let signaled = ended.terminationReason == .uncaughtSignal
                    let stopped = self.stopRequested.withLock { $0 }
                    guard signaled || ended.terminationStatus != 0, !stopped else {
                        continuation.finish()
                        return
                    }
                    continuation.finish(throwing: ExitFailure(
                        status: ended.terminationStatus,
                        standardError: io.collectedStandardError,
                        signaled: signaled))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        do {
            try process.run()
        } catch {

            _ = try? io.finishReading()
            throw error
        }

        self.process = process
        self.standardInput = input.fileHandleForWriting
        syncStandardInput.withLock { $0 = input.fileHandleForWriting }
        self.io = io
        return stream
    }

    public func write(_ line: Data) throws {
        guard standardInput != nil, process?.isRunning == true else { throw TransportError.notRunning }
        try writeSync(line)
    }

    public func endInput() {

        syncStandardInput.withLock { $0 = nil }
        try? standardInput?.close()
        standardInput = nil
    }

    nonisolated public func writeSync(_ line: Data) throws {
        try syncStandardInput.withLock { handle in
            guard let handle else { throw TransportError.notRunning }
            try handle.write(contentsOf: line + Data("\n".utf8))
        }
    }

    public func terminate() async {
        stopRequested.withLock { $0 = true }
        guard let process, process.isRunning else { return }
        process.terminate()
        if await waitForExit(process, within: terminationGracePeriod) { return }

        kill(process.processIdentifier, SIGKILL)
        _ = await waitForExit(process, within: killGracePeriod)
    }

    private func waitForExit(_ process: Process, within duration: Duration) async -> Bool {
        let deadline = ContinuousClock.now + duration
        while ContinuousClock.now < deadline {
            if !process.isRunning { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return !process.isRunning
    }
}
