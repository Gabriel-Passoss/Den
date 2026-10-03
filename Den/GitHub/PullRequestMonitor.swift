import Foundation
import Observation

@MainActor
@Observable
final class PullRequestMonitor {
    nonisolated struct Target: Hashable, Sendable {
        let session: UUID
        let path: String
    }

    struct Bar: Identifiable, Equatable {
        let repo: TaskWorktree.Repo
        let pullRequest: PullRequest
        var id: String { repo.id }
    }

    nonisolated private struct Item: Sendable {
        let target: Target
        let branch: String
        let directory: URL
        let host: String
    }

    static let visibleInterval: TimeInterval = 20
    static let backgroundInterval: TimeInterval = 120
    static let followUpDelay: TimeInterval = 10
    static let recentWindow: TimeInterval = 7 * 24 * 60 * 60
    static let ceiling: TimeInterval = 30 * 60

    private(set) var cli: GitHubCLIState = .unknown
    private(set) var checked: [Target: Date] = [:]
    private(set) var hiddenSetup: Set<UUID> = []

    @ObservationIgnored private let ledger: TaskLedger
    @ObservationIgnored private let fetcher: any PullRequestFetching
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let limit: Int
    @ObservationIgnored private var visible: [UUID: Int] = [:]
    @ObservationIgnored private var activity: [UUID: Date] = [:]
    @ObservationIgnored private var due: [Target: Date] = [:]
    @ObservationIgnored private var followUps: [Target: Date] = [:]
    @ObservationIgnored private var inFlight: Set<Target> = []
    @ObservationIgnored private var askedHosts: Set<String> = []
    @ObservationIgnored private var watchedHosts: Set<String> = []
    @ObservationIgnored private var checkingStatus = false
    @ObservationIgnored private var refreshPending = false
    @ObservationIgnored private var penalty: Double = 1
    @ObservationIgnored private var loop: Task<Void, Never>?

    init(ledger: TaskLedger, fetcher: any PullRequestFetching,
         now: @escaping () -> Date = Date.init, limit: Int = 3) {
        self.ledger = ledger
        self.fetcher = fetcher
        self.now = now
        self.limit = limit
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                Task { await self.tick() }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func tick() async {
        let all = items
        guard !all.isEmpty else { return }
        let hosts = Set(all.map(\.host))
        if cli == .unknown || !hosts.isSubset(of: askedHosts) {
            guard !checkingStatus else { return }
            checkingStatus = true
            if refreshPending {
                refreshPending = false
                await fetcher.refresh()
            }
            let status = await fetcher.status(hosts: hosts)
            checkingStatus = false
            apply(status, asked: hosts)
        }
        guard isReady else { return }
        let moment = now()
        let ready = all
            .filter { watchedHosts.contains($0.host) && !inFlight.contains($0.target) && isDue($0, at: moment) }
            .sorted { (due[$0.target] ?? .distantPast) < (due[$1.target] ?? .distantPast) }
            .prefix(max(0, limit - inFlight.count))
        guard !ready.isEmpty else { return }
        for item in ready { inFlight.insert(item.target) }
        let fetcher = self.fetcher
        await withTaskGroup(of: Void.self) { group in
            for item in ready {
                group.addTask {
                    let result = await fetcher.pullRequest(branch: item.branch, in: item.directory)
                    await self.finish(item, with: result)
                }
            }
        }
    }

    func appear(_ id: UUID) {
        visible[id, default: 0] += 1
        scheduleNow(id)
    }

    func disappear(_ id: UUID) {
        guard let count = visible[id] else { return }
        guard count == 1 else {
            visible[id] = count - 1
            return
        }
        visible[id] = nil
        for target in targets(of: id) {
            due[target] = interval(for: target).map { (checked[target] ?? now()).addingTimeInterval($0) }
        }
    }

    func turnEnded(_ id: UUID) {
        let moment = now()
        for target in targets(of: id) {
            due[target] = moment
            followUps[target] = moment.addingTimeInterval(Self.followUpDelay)
        }
    }

    func appBecameActive() {
        if !isReady {
            cli = .unknown
            refreshPending = true
        }
        for id in visible.keys { scheduleNow(id) }
    }

    func noteActivity(_ dates: [UUID: Date]) {
        activity.merge(dates) { max($0, $1) }
    }

    func refresh(_ id: UUID, repo: TaskWorktree.Repo) {
        due[Target(session: id, path: repo.worktree.path)] = now()
    }

    func reconfigure(path: String?) async {
        await fetcher.configure(path: path)
        hiddenSetup = []
        await checkGh()
        for id in visible.keys { scheduleNow(id) }
    }

    func checkGh() async {
        let hosts = Set(items.map(\.host)).union(["github.com"])
        apply(await fetcher.status(hosts: hosts), asked: hosts)
    }

    func pullRequests(for id: UUID) -> [Bar] {
        guard let worktree = ledger.worktree(for: id) else { return [] }
        let found = ledger.pullRequests(for: id)
        return worktree.repos.compactMap { repo in
            found[repo.worktree.path].map { Bar(repo: repo, pullRequest: $0) }
        }
    }

    func bars(for id: UUID) -> [Bar] {
        pullRequests(for: id).filter { bar in
            ledger.dismissedSignature(for: id, worktree: bar.repo.worktree.path)
                != PullRequestStatus.signature(bar.pullRequest)
        }
    }

    func dismiss(_ id: UUID, repo: TaskWorktree.Repo) {
        guard let pr = ledger.pullRequests(for: id)[repo.worktree.path] else { return }
        ledger.dismiss(id, worktree: repo.worktree.path, signature: PullRequestStatus.signature(pr))
    }

    func checkedAt(_ id: UUID, repo: TaskWorktree.Repo) -> Date? {
        checked[Target(session: id, path: repo.worktree.path)]
    }

    func setupNeeded(for id: UUID) -> GitHubCLIState? {
        guard !hiddenSetup.contains(id),
              ledger.worktree(for: id)?.repos.contains(where: { $0.remote?.host == "github.com" }) == true
        else { return nil }
        switch cli {
        case .missing, .notLoggedIn: return cli
        case .unknown, .ready: return nil
        }
    }

    func hideSetup(for id: UUID) { hiddenSetup.insert(id) }

    private var isReady: Bool {
        if case .ready = cli { return true }
        return false
    }

    private var items: [Item] {
        ledger.entries.flatMap { id, entry in
            entry.worktree.repos.compactMap { repo in
                repo.remote.map {
                    Item(target: Target(session: id, path: repo.worktree.path),
                         branch: entry.worktree.branch, directory: repo.worktree, host: $0.host)
                }
            }
        }
    }

    private func targets(of id: UUID) -> [Target] {
        items.map(\.target).filter { $0.session == id }
    }

    private func scheduleNow(_ id: UUID) {
        let moment = now()
        for target in targets(of: id) { due[target] = moment }
    }

    private func apply(_ status: GitHubCLIStatus, asked hosts: Set<String>) {
        cli = status.state
        askedHosts = hosts
        watchedHosts = status.hosts
    }

    private func isDue(_ item: Item, at moment: Date) -> Bool {
        if let follow = followUps[item.target], follow <= moment { return true }
        if let next = due[item.target] { return next <= moment }
        return checked[item.target] == nil && interval(for: item.target) != nil
    }

    private func interval(for target: Target) -> TimeInterval? {
        let pr = ledger.pullRequests(for: target.session)[target.path]
        if let pr, pr.state != .open { return nil }
        if visible[target.session] != nil { return Self.visibleInterval }
        if pr != nil { return Self.backgroundInterval }
        if let last = activity[target.session], now().timeIntervalSince(last) < Self.recentWindow {
            return Self.backgroundInterval
        }
        return nil
    }

    private func finish(_ item: Item, with result: FetchResult) {
        inFlight.remove(item.target)
        let moment = now()
        switch result {
        case .found(let pr):
            ledger.setPullRequest(pr, for: item.target.session, worktree: item.target.path)
            checked[item.target] = moment
            penalty = 1
        case .failed(let rateLimited):
            if rateLimited { penalty = min(penalty * 2, Self.ceiling / Self.visibleInterval) }
        }
        if let follow = followUps[item.target], follow <= moment { followUps[item.target] = nil }
        if let interval = interval(for: item.target) {
            due[item.target] = moment.addingTimeInterval(min(interval * penalty, Self.ceiling))
        } else {
            due[item.target] = nil
        }
    }
}
