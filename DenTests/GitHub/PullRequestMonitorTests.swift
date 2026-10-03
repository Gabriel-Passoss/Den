import Testing
import Foundation
@testable import Den

@MainActor
private final class TestClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
private struct Rig {
    let monitor: PullRequestMonitor
    let ledger: TaskLedger
    let fetcher: FakeFetcher
    let clock: TestClock
    let ids: [UUID]
    let file: URL

    func repo(_ index: Int) -> TaskWorktree.Repo {
        ledger.worktree(for: ids[index])?.repos.first
            ?? TaskWorktree.Repo(name: "", original: file, worktree: file, base: "", remote: nil)
    }

    func ticked(after seconds: TimeInterval) async -> Int {
        clock.advance(seconds)
        await monitor.tick()
        return await fetcher.calls.count
    }
}

@MainActor
private func makeRig(sessions: Int = 1, host: String = "github.com", limit: Int = 3) -> Rig {
    let file = FileManager.default.temporaryDirectory
        .appending(path: "DenTests-" + UUID().uuidString).appending(path: "task-worktrees.json")
    let ledger = TaskLedger(store: TaskWorktreeStore(url: file))
    let ids = (0..<sessions).map { index -> UUID in
        let id = UUID()
        let path = URL(fileURLWithPath: "/wt/api/task-\(index)")
        ledger.record(TaskWorktree(
            branch: "den/task-\(index)", sessionDirectory: path, mirrorRoot: nil,
            repos: [TaskWorktree.Repo(name: "api", original: URL(fileURLWithPath: "/code/api"),
                                      worktree: path, base: "origin/main",
                                      remote: GitHubRemote(host: host, owner: "den", name: "api"))]),
            for: id)
        return id
    }
    let fetcher = FakeFetcher()
    let clock = TestClock()
    let monitor = PullRequestMonitor(ledger: ledger, fetcher: fetcher, now: { clock.now }, limit: limit)
    return Rig(monitor: monitor, ledger: ledger, fetcher: fetcher, clock: clock, ids: ids, file: file)
}

private func eventually(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<1_000 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return false
}

@MainActor
@Test func aVisibleSessionIsCheckedEveryTwentySeconds() async {
    let rig = makeRig()
    rig.monitor.appear(rig.ids[0])

    await rig.monitor.tick()
    #expect(await rig.ticked(after: 19) == 1)

    #expect(await rig.ticked(after: 1) == 2)
}

@MainActor
@Test func aHiddenSessionWithAnOpenPullRequestIsCheckedEveryTwoMinutes() async {
    let rig = makeRig()
    rig.ledger.setPullRequest(makePullRequest(), for: rig.ids[0], worktree: rig.repo(0).worktree.path)
    await rig.fetcher.answer(.found(makePullRequest()))

    await rig.monitor.tick()
    #expect(await rig.ticked(after: 119) == 1)

    #expect(await rig.ticked(after: 1) == 2)
}

@MainActor
@Test func anOldHiddenSessionWithoutPullRequestWaitsUntilOpened() async {
    let rig = makeRig()
    rig.monitor.noteActivity([rig.ids[0]: rig.clock.now.addingTimeInterval(-8 * 24 * 3600)])

    await rig.monitor.tick()
    #expect(await rig.fetcher.calls.isEmpty)

    rig.monitor.appear(rig.ids[0])
    await rig.monitor.tick()
    #expect(await rig.fetcher.calls.count == 1)
}

@MainActor
@Test func aRecentHiddenSessionWithoutPullRequestIsWatched() async {
    let rig = makeRig()
    rig.monitor.noteActivity([rig.ids[0]: rig.clock.now.addingTimeInterval(-24 * 3600)])

    await rig.monitor.tick()
    #expect(await rig.ticked(after: 119) == 1)

    #expect(await rig.ticked(after: 1) == 2)
}

@MainActor
@Test func theEndOfATurnChecksNowAndTenSecondsLater() async {
    let rig = makeRig()
    rig.monitor.appear(rig.ids[0])
    await rig.monitor.tick()

    rig.clock.advance(5)
    rig.monitor.turnEnded(rig.ids[0])
    await rig.monitor.tick()
    #expect(await rig.fetcher.calls.count == 2)

    #expect(await rig.ticked(after: 9) == 2)

    #expect(await rig.ticked(after: 1) == 3)
}

@MainActor
@Test func aMergedPullRequestIsNotCheckedAgainUntilReopened() async {
    let rig = makeRig()
    await rig.fetcher.answer(.found(makePullRequest(state: .merged)))
    rig.monitor.appear(rig.ids[0])
    await rig.monitor.tick()

    #expect(await rig.ticked(after: 600) == 1)

    rig.monitor.disappear(rig.ids[0])
    rig.monitor.appear(rig.ids[0])
    await rig.monitor.tick()
    #expect(await rig.fetcher.calls.count == 2)
}

@MainActor
@Test func aSessionStaysVisibleUntilItsLastWindowGoes() async {
    let rig = makeRig()
    rig.monitor.appear(rig.ids[0])
    rig.monitor.appear(rig.ids[0])
    await rig.monitor.tick()

    rig.monitor.disappear(rig.ids[0])
    #expect(await rig.ticked(after: 20) == 2)

    rig.monitor.disappear(rig.ids[0])
    #expect(await rig.ticked(after: 20) == 2)
}

@MainActor
@Test func neverMoreThanThreeChecksAtOnce() async {
    let rig = makeRig(sessions: 5)
    for id in rig.ids { rig.monitor.appear(id) }
    await rig.fetcher.holdFetches()

    let first = Task { await rig.monitor.tick() }
    #expect(await eventually { await rig.fetcher.running == 3 })
    await rig.monitor.tick()
    #expect(await rig.fetcher.calls.count == 3)

    await rig.fetcher.release()
    await first.value
    await rig.monitor.tick()

    #expect(await rig.fetcher.calls.count == 5)
    #expect(await rig.fetcher.peak == 3)
}

@MainActor
@Test func aSlowStatusCheckIsNotRepeatedMeanwhile() async {
    let rig = makeRig()
    rig.monitor.appear(rig.ids[0])
    await rig.fetcher.holdStatus()

    let first = Task { await rig.monitor.tick() }
    #expect(await eventually { await rig.fetcher.statusCalls == 1 })
    await rig.monitor.tick()
    await rig.monitor.tick()
    #expect(await rig.fetcher.statusCalls == 1)

    await rig.fetcher.release()
    await first.value
    #expect(rig.monitor.cli == .ready(path: "/fake/gh", version: "1.0"))
}

@MainActor
@Test func rateLimitsStretchTheIntervalUntilACheckWorks() async {
    let rig = makeRig()
    await rig.fetcher.answer(.failed(rateLimited: true))
    rig.monitor.appear(rig.ids[0])
    await rig.monitor.tick()

    #expect(await rig.ticked(after: 20) == 1)
    #expect(await rig.ticked(after: 20) == 2)

    await rig.fetcher.answer(.found(nil))
    #expect(await rig.ticked(after: 79) == 2)
    #expect(await rig.ticked(after: 1) == 3)

    #expect(await rig.ticked(after: 20) == 4)
}

@MainActor
@Test func aDismissedBarComesBackWhenTheStateChanges() async {
    let rig = makeRig()
    await rig.fetcher.answer(.found(makePullRequest(checks: [.passed])))
    rig.monitor.appear(rig.ids[0])
    await rig.monitor.tick()
    #expect(rig.monitor.bars(for: rig.ids[0]).count == 1)

    rig.monitor.dismiss(rig.ids[0], repo: rig.repo(0))
    #expect(rig.monitor.bars(for: rig.ids[0]).isEmpty)
    #expect(rig.monitor.pullRequests(for: rig.ids[0]).count == 1)

    await rig.fetcher.answer(.found(makePullRequest(checks: [.failed])))
    rig.clock.advance(20)
    await rig.monitor.tick()
    #expect(rig.monitor.bars(for: rig.ids[0]).count == 1)
    #expect(rig.monitor.checkedAt(rig.ids[0], repo: rig.repo(0)) == rig.clock.now)
}

@MainActor
@Test func aMissingGhStopsTheChecksUntilItIsBack() async {
    let rig = makeRig()
    await rig.fetcher.set(state: .missing)
    rig.monitor.appear(rig.ids[0])
    await rig.monitor.tick()

    #expect(rig.monitor.cli == .missing)
    #expect(rig.monitor.setupNeeded(for: rig.ids[0]) == .missing)
    #expect(await rig.fetcher.calls.isEmpty)

    await rig.fetcher.set(state: .ready(path: "/fake/gh", version: "1.0"))
    rig.monitor.appBecameActive()
    await rig.monitor.tick()
    #expect(rig.monitor.setupNeeded(for: rig.ids[0]) == nil)
    #expect(await rig.fetcher.calls.count == 1)
}

@MainActor
@Test func reconfiguringHandsThePathOverAndChecksAgain() async {
    let rig = makeRig()
    await rig.fetcher.set(state: .missing)
    rig.monitor.appear(rig.ids[0])
    await rig.monitor.tick()
    rig.monitor.hideSetup(for: rig.ids[0])
    #expect(rig.monitor.setupNeeded(for: rig.ids[0]) == nil)

    await rig.fetcher.set(state: .notLoggedIn(host: "github.com"))
    await rig.monitor.reconfigure(path: "/opt/gh")

    #expect(await rig.fetcher.configured == ["/opt/gh"])
    #expect(rig.monitor.cli == .notLoggedIn(host: "github.com"))
    #expect(rig.monitor.setupNeeded(for: rig.ids[0]) == .notLoggedIn(host: "github.com"))
}

@MainActor
@Test func onlyLoggedInHostsAreWatched() async {
    let rig = makeRig(host: "git.acme.com")
    rig.monitor.appear(rig.ids[0])
    await rig.monitor.tick()

    #expect(await rig.fetcher.calls.isEmpty)
    #expect(rig.monitor.setupNeeded(for: rig.ids[0]) == nil)
}

@MainActor
@Test func noWorktreesMeansNoGhAtAll() async {
    let rig = makeRig(sessions: 0)
    await rig.monitor.tick()

    #expect(await rig.fetcher.statusCalls == 0)
    #expect(rig.monitor.cli == .unknown)
}

@MainActor
@Test func comingBackToTheAppRefreshesGhBeforeCheckingAgain() async {
    let rig = makeRig()
    await rig.fetcher.set(state: .missing)
    rig.monitor.appear(rig.ids[0])
    await rig.monitor.tick()
    #expect(await rig.fetcher.refreshes == 0)

    rig.monitor.appBecameActive()
    await rig.monitor.tick()

    #expect(await rig.fetcher.refreshes == 1)
    #expect(await rig.fetcher.statusCalls == 2)
}

@MainActor
@Test func comingBackWhileReadyLeavesGhAlone() async {
    let rig = makeRig()
    rig.monitor.appear(rig.ids[0])
    await rig.monitor.tick()

    rig.monitor.appBecameActive()
    await rig.monitor.tick()

    #expect(await rig.fetcher.refreshes == 0)
}
