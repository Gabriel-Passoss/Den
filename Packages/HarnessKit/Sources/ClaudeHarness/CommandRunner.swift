import Foundation

/// Executa um comando e devolve o stdout. Injetável para que a descoberta
/// possa ser testada sem depender do que está instalado na máquina.
public protocol CommandRunner: Sendable {
    func run(_ executable: String, _ arguments: [String]) async throws -> String
}

public struct SystemCommandRunner: CommandRunner {
    public init() {}

    public func run(_ executable: String, _ arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw CocoaError(.executableLoad)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
