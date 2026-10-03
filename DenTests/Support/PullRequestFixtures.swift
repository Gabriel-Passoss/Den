import Foundation
@testable import Den

func makePullRequest(number: Int = 1, state: PullRequest.State = .open, isDraft: Bool = false,
                     review: PullRequest.Review = .undecided,
                     mergeable: PullRequest.Mergeable = .mergeable,
                     checks: [CheckRun.State] = []) -> PullRequest {
    PullRequest(number: number, title: "PR \(number)",
                url: URL(string: "https://github.com/den/api/pull/\(number)") ?? URL(fileURLWithPath: "/"),
                state: state, isDraft: isDraft, additions: 10, deletions: 2, base: "main",
                review: review, mergeable: mergeable,
                checks: checks.enumerated().map { index, state in
                    CheckRun(name: "check-\(index)", workflow: "CI", state: state,
                             startedAt: nil, completedAt: nil, url: nil)
                },
                updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
}
