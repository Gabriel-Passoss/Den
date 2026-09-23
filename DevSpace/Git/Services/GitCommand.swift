import Foundation

nonisolated enum GitCommand {
    static func run(_ arguments: [String], in directory: URL) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do { try process.run() } catch { return nil }

        async let outData = drain(stdout.fileHandleForReading)
        async let errData = drain(stderr.fileHandleForReading)
        let code = await exitCode(of: process)
        let data = await outData
        _ = await errData

        guard code == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func drain(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: handle.readDataToEndOfFile())
            }
        }
    }

    private static func exitCode(of process: Process) async -> Int32 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus)
            }
        }
    }
}
