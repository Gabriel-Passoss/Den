import Foundation
import HarnessCore

nonisolated enum GitCommand {
    static func run(_ arguments: [String], in directory: URL) async -> String? {
        try? await SystemCommandRunner().run("/usr/bin/git", ["-C", directory.path] + arguments)
    }
}
