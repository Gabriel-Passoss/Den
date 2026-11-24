import Foundation
import DenStore

nonisolated struct TaskWorktreeEntry: Codable, Equatable, Sendable {
    static let documentKind = "task-worktree"

    var worktree: TaskWorktree
    var pullRequests: [String: PullRequest]
    var dismissed: [String: String]

    init(worktree: TaskWorktree, pullRequests: [String: PullRequest] = [:],
         dismissed: [String: String] = [:]) {
        self.worktree = worktree
        self.pullRequests = pullRequests
        self.dismissed = dismissed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        worktree = try container.decode(TaskWorktree.self, forKey: .worktree)
        pullRequests = try container.decodeIfPresent([String: PullRequest].self, forKey: .pullRequests) ?? [:]
        dismissed = try container.decodeIfPresent([String: String].self, forKey: .dismissed) ?? [:]
    }
}

extension Repositories {
    nonisolated var taskWorktrees: any SessionDocumentRepository<TaskWorktreeEntry> {
        documents(kind: TaskWorktreeEntry.documentKind, as: TaskWorktreeEntry.self)
    }
}
