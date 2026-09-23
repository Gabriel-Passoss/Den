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

        try process.run()

        async let stdoutData = Self.readAll(stdoutPipe.fileHandleForReading)
        async let stderrData = Self.readAll(stderrPipe.fileHandleForReading)
        let (outData, errData) = await (stdoutData, stderrData)

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw CommandFailure(exitCode: process.terminationStatus, stderr: String(decoding: errData, as: UTF8.self))
        }
        return String(decoding: outData, as: UTF8.self)
    }

    private static func readAll(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: handle.readDataToEndOfFile())
            }
        }
    }
}
