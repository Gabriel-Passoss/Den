import Foundation

/// Executa um comando e devolve o stdout. Injetável para que a descoberta
/// possa ser testada sem depender do que está instalado na máquina.
public protocol CommandRunner: Sendable {
    func run(_ executable: String, _ arguments: [String]) async throws -> String
}

/// O processo terminou com código diferente de zero. Carrega o stderr
/// capturado porque é o único jeito de distinguir, por exemplo, uma falha de
/// autenticação de qualquer outro erro (spec §5.3).
public struct CommandFailure: Error, Equatable {
    public let exitCode: Int32
    public let stderr: String
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

        // stderr precisa ser drenado sempre (spec §4.4): o pipe do SO tem um
        // teto (~64 KiB). Se só lermos o stdout, um filho que escreve bastante
        // em stderr antes de terminar trava escrevendo, nunca fecha o stdout,
        // e `readDataToEndOfFile()` do outro lado espera para sempre. Lendo os
        // dois em paralelo, nenhum pipe pode travar o outro.
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
