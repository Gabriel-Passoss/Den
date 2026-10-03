import Foundation
@testable import Den

struct GitCommandFailed: Error, CustomStringConvertible {
    let description: String
}

struct TestRepository {
    let checkout: URL
    let origin: URL
    let seed: URL
}

@discardableResult
func runGit(_ arguments: [String], in directory: URL) async throws -> String {
    let outcome = await TimedProcess.run("/usr/bin/git", [
        "-C", directory.path, "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null",
        "-c", "user.name=Den Tests", "-c", "user.email=tests@den.invalid",
    ] + arguments, timeout: .seconds(30))
    guard let outcome, outcome.succeeded else {
        throw GitCommandFailed(description: "git \(arguments.joined(separator: " ")): "
                               + (outcome?.errorLine ?? "sem resposta"))
    }
    return outcome.output
}

func gitSucceeds(_ arguments: [String], in directory: URL) async -> Bool {
    await TimedProcess.run("/usr/bin/git", ["-C", directory.path] + arguments,
                           timeout: .seconds(30))?.succeeded == true
}

@discardableResult
func makeRepository(at checkout: URL, scratch: URL,
                    defaultBranch: String = "main") async throws -> TestRepository {
    let tag = String(UUID().uuidString.prefix(6))
    let seed = scratch.appending(path: "seed-\(checkout.lastPathComponent)-\(tag)")
    let origin = scratch.appending(path: "\(checkout.lastPathComponent)-\(tag).git")
    try FileManager.default.createDirectory(at: seed, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: checkout.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try await runGit(["init", "-q", "-b", defaultBranch], in: seed)
    try "hello\n".write(to: seed.appending(path: "README.md"), atomically: true, encoding: .utf8)
    try await runGit(["add", "."], in: seed)
    try await runGit(["commit", "-q", "-m", "initial"], in: seed)
    try await runGit(["clone", "-q", "--bare", seed.path, origin.path], in: scratch)
    try await runGit(["clone", "-q", origin.path, checkout.path], in: scratch)
    return TestRepository(checkout: checkout, origin: origin, seed: seed)
}
