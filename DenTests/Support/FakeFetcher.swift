import Foundation
@testable import Den

actor FakeFetcher: PullRequestFetching {
    private(set) var calls: [String] = []
    private(set) var statusCalls = 0
    private(set) var configured: [String?] = []
    private(set) var running = 0
    private(set) var peak = 0
    private(set) var refreshes = 0
    private var state: GitHubCLIState = .ready(path: "/fake/gh", version: "1.0")
    private let loggedIn: Set<String> = ["github.com"]
    private var fallback: FetchResult = .found(nil)
    private var holdingFetches = false
    private var holdingStatus = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func set(state: GitHubCLIState) { self.state = state }
    func answer(_ result: FetchResult) { fallback = result }
    func holdFetches() { holdingFetches = true }
    func holdStatus() { holdingStatus = true }

    func release() {
        holdingFetches = false
        holdingStatus = false
        let waiters = waiting
        waiting = []
        for waiter in waiters { waiter.resume() }
    }

    func status(hosts: Set<String>) async -> GitHubCLIStatus {
        statusCalls += 1
        if holdingStatus { await withCheckedContinuation { waiting.append($0) } }
        return GitHubCLIStatus(state: state, hosts: hosts.intersection(loggedIn))
    }

    func pullRequest(branch: String, in directory: URL) async -> FetchResult {
        calls.append(directory.path)
        running += 1
        peak = max(peak, running)
        if holdingFetches { await withCheckedContinuation { waiting.append($0) } }
        running -= 1
        return fallback
    }

    func configure(path: String?) async { configured.append(path) }

    func refresh() async { refreshes += 1 }
}
