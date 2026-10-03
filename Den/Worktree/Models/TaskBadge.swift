import Foundation

nonisolated struct TaskBadge: Equatable {
    var tone: PullRequestTone?
    var detail: String

    static func make(worktree: TaskWorktree, pullRequests: [PullRequest]) -> TaskBadge {
        guard let worst = PullRequestStatus.worst(pullRequests) else {
            return TaskBadge(detail: "⑂ " + worktree.branch)
        }
        let head = pullRequests.count == 1 ? "#\(worst.number)" : "\(pullRequests.count) PRs"
        return TaskBadge(tone: PullRequestStatus.tone(worst),
                         detail: "\(head) · \(PullRequestStatus.label(worst))")
    }
}
