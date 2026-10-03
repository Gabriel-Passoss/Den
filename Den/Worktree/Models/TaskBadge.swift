import Foundation

nonisolated struct TaskBadge: Equatable {
    var tone: PullRequestTone? = nil
    var tag: String? = nil
    var detail: String
}
