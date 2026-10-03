import Foundation

nonisolated struct TaskBadge: Equatable {
    var tone: PullRequestTone? = nil
    var detail: String
}
