import Foundation

nonisolated struct TaskWorktree: Codable, Equatable, Sendable {
    struct Repo: Codable, Equatable, Sendable, Identifiable {
        var id: String { worktree.path }
        var name: String
        var original: URL
        var worktree: URL
        var base: String
        var remote: GitHubRemote?
    }

    var branch: String
    var sessionDirectory: URL
    var mirrorRoot: URL?
    var repos: [Repo]

    private var home: URL { mirrorRoot ?? repos.first?.worktree ?? sessionDirectory }

    var folderName: String { home.lastPathComponent }

    var displayLocation: String { (home.path as NSString).abbreviatingWithTildeInPath }
}
