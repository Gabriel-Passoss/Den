import Testing
import Foundation
@testable import Den

private let rich = #"""
[
  {
    "number": 80,
    "title": "Melhorias nos seletores de data",
    "url": "https://github.com/den/app/pull/80",
    "state": "OPEN",
    "isDraft": false,
    "additions": 220,
    "deletions": 7,
    "baseRefName": "main",
    "reviewDecision": "APPROVED",
    "mergeable": "MERGEABLE",
    "updatedAt": "2026-09-30T12:00:00Z",
    "statusCheckRollup": [
      {"__typename": "CheckRun", "name": "lint", "workflowName": "CI", "status": "COMPLETED",
       "conclusion": "FAILURE", "detailsUrl": "https://github.com/den/app/actions/runs/1/job/1",
       "startedAt": "2026-09-30T11:00:00Z", "completedAt": "2026-09-30T11:00:42Z"},
      {"__typename": "CheckRun", "name": "build", "workflowName": "CI", "status": "COMPLETED",
       "conclusion": "SUCCESS", "detailsUrl": "https://github.com/den/app/actions/runs/1/job/2",
       "startedAt": "2026-09-30T11:00:00Z", "completedAt": "2026-09-30T11:03:10Z"},
      {"__typename": "CheckRun", "name": "e2e", "workflowName": "CI", "status": "IN_PROGRESS",
       "conclusion": "", "detailsUrl": "https://github.com/den/app/actions/runs/1/job/3",
       "startedAt": "2026-09-30T11:00:00Z", "completedAt": "0001-01-01T00:00:00Z"},
      {"__typename": "CheckRun", "name": "deploy", "workflowName": "CD", "status": "QUEUED",
       "conclusion": "", "detailsUrl": "", "startedAt": "0001-01-01T00:00:00Z",
       "completedAt": "0001-01-01T00:00:00Z"},
      {"__typename": "CheckRun", "name": "docs", "workflowName": "CI", "status": "COMPLETED",
       "conclusion": "SKIPPED", "detailsUrl": "https://github.com/den/app/actions/runs/1/job/5",
       "startedAt": "2026-09-30T11:00:00Z", "completedAt": "2026-09-30T11:00:01Z"},
      {"__typename": "StatusContext", "context": "vercel", "state": "PENDING",
       "targetUrl": "https://vercel.com/den/app/1", "startedAt": "2026-09-30T11:00:00Z"}
    ]
  }
]
"""#

private func entry(number: Int, state: String, updatedAt: String, isDraft: Bool = false) -> String {
    """
    {"number": \(number), "title": "PR \(number)", "url": "https://github.com/den/app/pull/\(number)",
     "state": "\(state)", "isDraft": \(isDraft), "additions": 1, "deletions": 0, "baseRefName": "main",
     "reviewDecision": "", "mergeable": "UNKNOWN", "updatedAt": "\(updatedAt)", "statusCheckRollup": null}
    """
}

private func parse(_ text: String) throws -> PullRequest? {
    try PullRequestQuery.parse(Data(text.utf8))
}

@Test func theQueryAsksForThisBranchInEveryState() {
    let arguments = PullRequestQuery.arguments(branch: "den/NS-1-fix")
    #expect(arguments.starts(with: ["pr", "list", "--head", "den/NS-1-fix", "--state", "all"]))
    #expect(arguments.last?.contains("statusCheckRollup") == true)
    #expect(arguments.last?.contains("baseRefName") == true)
}

@Test func aRichListIsReadIntoOnePullRequest() throws {
    let pr = try #require(try parse(rich))

    #expect(pr.number == 80)
    #expect(pr.state == .open)
    #expect(pr.review == .approved)
    #expect(pr.mergeable == .mergeable)
    #expect(pr.additions == 220 && pr.deletions == 7)
    #expect(pr.base == "main")
    #expect(pr.checks.map(\.state) == [.failed, .passed, .running, .queued, .skipped, .running])
    #expect(pr.checks[0].workflow == "CI")
    #expect(pr.checks[0].url?.absoluteString == "https://github.com/den/app/actions/runs/1/job/1")
    #expect(pr.checks[2].completedAt == nil)
    #expect(pr.checks[3].startedAt == nil)
    #expect(pr.checks[3].url == nil)
    #expect(pr.checks[5].name == "vercel")
    #expect(pr.checks[5].workflow == nil)
    #expect(pr.checks[5].url?.host() == "vercel.com")
}

@Test func anEmptyListMeansNoPullRequest() throws {
    #expect(try parse("[]") == nil)
}

@Test func theStatesAndDecisionsAreMapped() throws {
    #expect(try parse("[\(entry(number: 1, state: "MERGED", updatedAt: "2026-09-30T12:00:00Z"))]")?.state == .merged)
    #expect(try parse("[\(entry(number: 1, state: "CLOSED", updatedAt: "2026-09-30T12:00:00Z"))]")?.state == .closed)
    let draft = try #require(try parse("[\(entry(number: 1, state: "OPEN", updatedAt: "2026-09-30T12:00:00Z", isDraft: true))]"))
    #expect(draft.isDraft)
    #expect(draft.review == .undecided)
    #expect(draft.mergeable == .unknown)
    #expect(draft.checks.isEmpty)
}

@Test func anOpenPullRequestWinsOverANewerClosedOne() throws {
    let list = "[\(entry(number: 1, state: "MERGED", updatedAt: "2026-09-30T12:00:00Z")),"
        + "\(entry(number: 2, state: "OPEN", updatedAt: "2026-09-01T12:00:00Z"))]"
    #expect(try parse(list)?.number == 2)
}

@Test func withoutAnOpenOneTheNewestWins() throws {
    let list = "[\(entry(number: 1, state: "CLOSED", updatedAt: "2026-09-01T12:00:00Z")),"
        + "\(entry(number: 2, state: "MERGED", updatedAt: "2026-09-30T12:00:00Z"))]"
    #expect(try parse(list)?.number == 2)
}

@Test func reviewDecisionsAreRead() throws {
    func review(_ decision: String) throws -> PullRequest.Review? {
        try parse(rich.replacingOccurrences(of: "\"APPROVED\"", with: "\"\(decision)\""))?.review
    }
    #expect(try review("CHANGES_REQUESTED") == .changesRequested)
    #expect(try review("REVIEW_REQUIRED") == .required)
    #expect(try review("") == PullRequest.Review.undecided)
    #expect(try parse(rich.replacingOccurrences(of: "\"MERGEABLE\"", with: "\"CONFLICTING\""))?
        .mergeable == .conflicting)
}

@Test func somethingThatIsNotAListThrows() {
    #expect(throws: (any Error).self) { try parse("{\"message\": \"Not Found\"}") }
}
