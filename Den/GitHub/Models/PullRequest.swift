import Foundation

nonisolated struct CheckRun: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case queued, running, passed, failed, skipped
    }

    var name: String
    var workflow: String?
    var state: State
    var startedAt: Date?
    var completedAt: Date?
    var url: URL?
}

nonisolated struct PullRequest: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case open, closed, merged
    }

    enum Review: String, Codable, Sendable {
        case undecided = "none", required, approved, changesRequested
    }

    enum Mergeable: String, Codable, Sendable {
        case mergeable, conflicting, unknown
    }

    var number: Int
    var title: String
    var url: URL
    var state: State
    var isDraft: Bool
    var additions: Int
    var deletions: Int
    var base: String
    var review: Review
    var mergeable: Mergeable
    var checks: [CheckRun]
    var updatedAt: Date
}
