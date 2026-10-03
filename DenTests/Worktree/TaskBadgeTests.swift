import Testing
@testable import Den

@Test func aTaskWithoutAPullRequestShowsItsBranch() {
    let badge = TaskBadge.make(worktree: sampleWorktree(branch: "fix/login"), pullRequests: [])

    #expect(badge == TaskBadge(detail: "⑂ fix/login"))
}

@Test func aTaskWithOnePullRequestShowsItsNumberAndState() {
    let failing = makePullRequest(number: 80, checks: [.failed])

    let badge = TaskBadge.make(worktree: sampleWorktree(), pullRequests: [failing])

    #expect(badge.tone == .failure)
    #expect(badge.detail == "#80 · Checks falhando")
}

@Test func aTaskWithSeveralPullRequestsShowsTheWorstOne() {
    let merged = makePullRequest(number: 1, state: .merged)
    let failing = makePullRequest(number: 2, checks: [.failed])

    let badge = TaskBadge.make(worktree: sampleWorktree(), pullRequests: [merged, failing])

    #expect(badge.tone == .failure)
    #expect(badge.detail == "2 PRs · Checks falhando")
}
