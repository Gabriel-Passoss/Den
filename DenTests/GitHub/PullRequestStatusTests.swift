import Testing
import Foundation
@testable import Den

@Test func theChecksSummaryIgnoresSkippedOnes() {
    #expect(PullRequestStatus.checks(makePullRequest()) == ChecksSummary.none)
    #expect(PullRequestStatus.checks(makePullRequest(checks: [.passed, .skipped, .passed]))
            == .passing(total: 2))
    #expect(PullRequestStatus.checks(makePullRequest(checks: [.passed, .running, .queued]))
            == .running(passed: 1, total: 3))
    #expect(PullRequestStatus.checks(makePullRequest(checks: [.failed, .passed, .running, .skipped]))
            == .failing(passed: 1, total: 3))
}

@Test func everyToneOfTheTable() {
    #expect(PullRequestStatus.tone(makePullRequest(checks: [.failed])) == .failure)
    #expect(PullRequestStatus.tone(makePullRequest(review: .changesRequested)) == .attention)
    #expect(PullRequestStatus.tone(makePullRequest(mergeable: .conflicting)) == .attention)
    #expect(PullRequestStatus.tone(makePullRequest(isDraft: true, checks: [.failed])) == .draft)
    #expect(PullRequestStatus.tone(makePullRequest(checks: [.running])) == .open)
    #expect(PullRequestStatus.tone(makePullRequest(state: .closed)) == .closed)
    #expect(PullRequestStatus.tone(makePullRequest(state: .merged)) == .merged)
}

@Test func theWorstOfSeveralWinsAndMergedOnlyWhenAllAre() {
    let merged = makePullRequest(number: 1, state: .merged)
    let failing = makePullRequest(number: 2, checks: [.failed])
    let open = makePullRequest(number: 3)
    #expect(PullRequestStatus.worst([merged, failing, open])?.number == 2)
    #expect(PullRequestStatus.worst([merged, open])?.number == 3)
    #expect(PullRequestStatus.worst([merged, makePullRequest(number: 4, state: .merged)])
        .map(PullRequestStatus.tone) == .merged)
    #expect(PullRequestStatus.worst([]) == nil)
}

@Test func labelsFollowTheirPrecedence() {
    #expect(PullRequestStatus.label(makePullRequest(state: .merged)) == "Mergeado")
    #expect(PullRequestStatus.label(makePullRequest(state: .closed)) == "Fechado")
    #expect(PullRequestStatus.label(makePullRequest(isDraft: true)) == "Rascunho")
    #expect(PullRequestStatus.label(makePullRequest(mergeable: .conflicting, checks: [.failed]))
            == "Checks falhando")
    #expect(PullRequestStatus.label(makePullRequest(review: .changesRequested, mergeable: .conflicting))
            == "Conflito")
    #expect(PullRequestStatus.label(makePullRequest(review: .changesRequested)) == "Mudanças pedidas")
    #expect(PullRequestStatus.label(makePullRequest(review: .approved, checks: [.running]))
            == "Checks rodando")
    #expect(PullRequestStatus.label(makePullRequest(review: .approved, checks: [.passed]))
            == "Pronto para merge")
    #expect(PullRequestStatus.label(makePullRequest()) == "Aberto")
}

@Test func theSignatureMovesWithTheStateButNotWithEachCheck() {
    let one = PullRequestStatus.signature(makePullRequest(checks: [.passed, .running]))
    let two = PullRequestStatus.signature(makePullRequest(checks: [.passed, .passed, .running]))
    let failing = PullRequestStatus.signature(makePullRequest(checks: [.failed, .running]))
    #expect(one == two)
    #expect(one != failing)
    #expect(PullRequestStatus.signature(makePullRequest(state: .merged)) != one)
}

@Test func checksAreOrderedFailedFirstAndStableWithinAGroup() {
    let pr = makePullRequest(checks: [.passed, .skipped, .failed, .queued, .running, .passed])
    #expect(PullRequestStatus.ordered(pr.checks).map(\.name)
            == ["check-2", "check-4", "check-3", "check-0", "check-5", "check-1"])
}

@Test func theHeadlineCountsWhatMatters() {
    #expect(PullRequestStatus.headline(makePullRequest(checks: [.failed, .running, .passed]))
            == "1 falhou · 1 rodando")
    #expect(PullRequestStatus.headline(makePullRequest(checks: [.failed, .failed])) == "2 falharam")
    #expect(PullRequestStatus.headline(makePullRequest(checks: [.passed, .passed, .skipped]))
            == "2 de 2 passaram")
    #expect(PullRequestStatus.headline(makePullRequest()) == "Nenhum check")
}

@Test func aCheckDescribesItsWorkflowAndDuration() {
    let start = Date(timeIntervalSince1970: 1_000)
    let finished = CheckRun(name: "test", workflow: "CI", state: .passed, startedAt: start,
                            completedAt: start.addingTimeInterval(302), url: nil)
    let running = CheckRun(name: "e2e", workflow: nil, state: .running, startedAt: start,
                           completedAt: nil, url: nil)
    let queued = CheckRun(name: "deploy", workflow: "CD", state: .queued, startedAt: nil,
                          completedAt: nil, url: nil)
    let skipped = CheckRun(name: "docs", workflow: "CI", state: .skipped, startedAt: start,
                           completedAt: start, url: nil)
    let now = start.addingTimeInterval(42)

    #expect(PullRequestStatus.detail(of: finished, at: now) == "CI · 5min 02s")
    #expect(PullRequestStatus.detail(of: running, at: now) == "42s")
    #expect(PullRequestStatus.detail(of: queued, at: now) == "CD · na fila")
    #expect(PullRequestStatus.detail(of: skipped, at: now) == "Pulado")
}

@Test func theUpdatedLabelReadsLikeASentence() {
    let now = Date(timeIntervalSince1970: 10_000)
    #expect(PullRequestStatus.updatedLabel(since: nil, now: now) == "Ainda não atualizado")
    #expect(PullRequestStatus.updatedLabel(since: now.addingTimeInterval(-12), now: now) == "Atualizado há 12s")
    #expect(PullRequestStatus.updatedLabel(since: now.addingTimeInterval(-300), now: now) == "Atualizado há 5 min")
}
