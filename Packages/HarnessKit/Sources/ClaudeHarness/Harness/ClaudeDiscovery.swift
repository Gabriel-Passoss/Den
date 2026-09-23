import Foundation
import HarnessCore

public struct ClaudeDiscovery: Sendable {
    public enum DiscoveryError: Error, Equatable {
        case notFound
        case unreadableVersion(String)

        case versionCommandFailed(exitCode: Int32, stderr: String)
    }

    public static let defaultFallbackPaths = [
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        NSHomeDirectory() + "/.local/bin/claude",
        NSHomeDirectory() + "/.claude/local/claude",
    ]

    private let runner: CommandRunner
    private let shell: String
    private let fallbackPaths: [String]

    public init(
        runner: CommandRunner = SystemCommandRunner(),
        shell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
        fallbackPaths: [String] = ClaudeDiscovery.defaultFallbackPaths
    ) {
        self.runner = runner
        self.shell = shell
        self.fallbackPaths = fallbackPaths
    }

    public func discover() async throws -> HarnessInstallation {

        var firstUnreadableVersion: DiscoveryError?

        var firstCommandFailure: DiscoveryError?
        for candidate in try await candidates() {
            do {
                let version = try await readVersion(of: candidate)
                return HarnessInstallation(executable: candidate, version: version)
            } catch let error as DiscoveryError {
                if firstUnreadableVersion == nil, case .unreadableVersion = error {
                    firstUnreadableVersion = error
                }
                continue
            } catch let failure as CommandFailure {
                if firstCommandFailure == nil {
                    firstCommandFailure = .versionCommandFailed(
                        exitCode: failure.exitCode,
                        stderr: failure.stderr
                    )
                }
                continue
            } catch {
                continue
            }
        }

        throw firstUnreadableVersion ?? firstCommandFailure ?? DiscoveryError.notFound
    }

    private func candidates() async throws -> [String] {
        var found: [String] = []
        if let output = try? await runner.run(shell, ["-l", "-c", "command -v claude"]) {
            let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty { found.append(path) }
        }
        found.append(contentsOf: fallbackPaths)
        return found
    }

    private func readVersion(of executable: String) async throws -> String {
        let raw = try await runner.run(executable, ["--version"])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let match = raw.firstMatch(of: /^(\d+\.\d+\.\d+)/) else {
            throw DiscoveryError.unreadableVersion(raw)
        }
        return String(match.1)
    }
}
