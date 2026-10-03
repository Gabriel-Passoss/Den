import Foundation

nonisolated enum PullRequestQuery {
    static let fields = "number,title,url,state,isDraft,additions,deletions,baseRefName,"
        + "reviewDecision,mergeable,statusCheckRollup,updatedAt"

    static func arguments(branch: String) -> [String] {
        ["pr", "list", "--head", branch, "--state", "all", "--limit", "5", "--json", fields]
    }

    static func parse(_ data: Data) throws -> PullRequest? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            return ISO8601DateFormatter().date(from: text) ?? Date(timeIntervalSince1970: 0)
        }
        let raws = try decoder.decode([RawPullRequest].self, from: data)
        let open = raws.filter { $0.state == "OPEN" }.max { $0.updatedAt < $1.updatedAt }
        return (open ?? raws.max { $0.updatedAt < $1.updatedAt })?.pullRequest
    }

    private struct RawPullRequest: Decodable {
        let number: Int
        let title: String
        let url: URL
        let state: String
        let isDraft: Bool
        let additions: Int
        let deletions: Int
        let baseRefName: String?
        let reviewDecision: String?
        let mergeable: String?
        let statusCheckRollup: [RawCheck]?
        let updatedAt: Date

        var pullRequest: PullRequest {
            PullRequest(number: number, title: title, url: url,
                        state: state == "OPEN" ? .open : state == "MERGED" ? .merged : .closed,
                        isDraft: isDraft, additions: additions, deletions: deletions,
                        base: baseRefName ?? "",
                        review: PullRequestQuery.review(reviewDecision),
                        mergeable: mergeable == "MERGEABLE" ? .mergeable
                            : mergeable == "CONFLICTING" ? .conflicting : .unknown,
                        checks: (statusCheckRollup ?? []).map(\.checkRun),
                        updatedAt: updatedAt)
        }
    }

    private struct RawCheck: Decodable {
        let typename: String?
        let name: String?
        let workflowName: String?
        let status: String?
        let conclusion: String?
        let detailsUrl: String?
        let context: String?
        let state: String?
        let targetUrl: String?
        let startedAt: Date?
        let completedAt: Date?

        enum CodingKeys: String, CodingKey {
            case typename = "__typename"
            case name, workflowName, status, conclusion, detailsUrl, context, state, targetUrl
            case startedAt, completedAt
        }

        var checkRun: CheckRun {
            let isContext = typename == "StatusContext" || context != nil
            let link = isContext ? targetUrl : detailsUrl
            return CheckRun(
                name: (isContext ? context : name) ?? "check",
                workflow: isContext ? nil : workflowName.flatMap { $0.isEmpty ? nil : $0 },
                state: isContext ? PullRequestQuery.contextState(state)
                    : PullRequestQuery.runState(status: status, conclusion: conclusion),
                startedAt: PullRequestQuery.real(startedAt),
                completedAt: PullRequestQuery.real(completedAt),
                url: link.flatMap { $0.isEmpty ? nil : URL(string: $0) })
        }
    }

    private static func review(_ decision: String?) -> PullRequest.Review {
        switch decision {
        case "APPROVED": .approved
        case "CHANGES_REQUESTED": .changesRequested
        case "REVIEW_REQUIRED": .required
        default: .none
        }
    }

    private static func runState(status: String?, conclusion: String?) -> CheckRun.State {
        switch status?.uppercased() ?? "" {
        case "IN_PROGRESS": return .running
        case "COMPLETED": break
        default: return .queued
        }
        switch conclusion?.uppercased() ?? "" {
        case "SUCCESS": return .passed
        case "SKIPPED", "NEUTRAL", "STALE": return .skipped
        default: return .failed
        }
    }

    private static func contextState(_ state: String?) -> CheckRun.State {
        switch state?.uppercased() ?? "" {
        case "SUCCESS": .passed
        case "FAILURE", "ERROR": .failed
        default: .running
        }
    }

    private static func real(_ date: Date?) -> Date? {
        guard let date, date.timeIntervalSince1970 > 0 else { return nil }
        return date
    }
}
