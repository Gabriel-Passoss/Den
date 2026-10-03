import Foundation

nonisolated enum GitHubCLIState: Equatable, Sendable {
    case unknown
    case missing
    case notLoggedIn(host: String)
    case ready(path: String, version: String)
}

nonisolated struct GitHubCLIStatus: Equatable, Sendable {
    var state: GitHubCLIState
    var hosts: Set<String>
}

nonisolated enum FetchResult: Equatable, Sendable {
    case found(PullRequest?)
    case failed(rateLimited: Bool)
}

nonisolated protocol PullRequestFetching: Sendable {
    func status(hosts: Set<String>) async -> GitHubCLIStatus
    func pullRequest(branch: String, in directory: URL) async -> FetchResult
    func configure(path: String?) async
    func refresh() async
}

actor GitHubCLI: PullRequestFetching {
    typealias Runner = @Sendable (_ executable: String, _ arguments: [String], _ directory: URL?,
                                  _ environment: [String: String]?, _ timeout: Duration) async -> ProcessOutcome?

    nonisolated static let pathKey = "Den.ghPath"
    nonisolated static let defaultCandidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
    nonisolated static let quiet = ["GH_PROMPT_DISABLED": "1", "GH_NO_UPDATE_NOTIFIER": "1", "NO_COLOR": "1"]

    private struct Location: Sendable {
        let path: String
        let version: String
    }

    private let override: String?
    private var configured: String?
    private let shell: ShellEnvironment
    private let candidates: [String]
    private let timeout: Duration
    private let runner: Runner
    private var locating: Task<Location?, Never>?
    private var logins: [String: Bool] = [:]

    init(override: String? = nil, configured: String? = nil, shell: ShellEnvironment = .shared,
         candidates: [String] = GitHubCLI.defaultCandidates, timeout: Duration = .seconds(15),
         runner: @escaping Runner = { executable, arguments, directory, environment, timeout in
             await TimedProcess.run(executable, arguments, in: directory, environment: environment,
                                    timeout: timeout)
         }) {
        self.override = override
        self.configured = configured
        self.shell = shell
        self.candidates = candidates
        self.timeout = timeout
        self.runner = runner
    }

    func configure(path: String?) {
        configured = path
        refresh()
    }

    func refresh() {
        locating = nil
        logins = [:]
    }

    func status(hosts: Set<String>) async -> GitHubCLIStatus {
        guard let location = await locate() else { return GitHubCLIStatus(state: .missing, hosts: []) }
        var loggedIn: Set<String> = []
        for host in hosts.sorted() {
            if await isLoggedIn(host, with: location.path) { loggedIn.insert(host) }
        }
        if hosts.contains("github.com"), !loggedIn.contains("github.com") {
            return GitHubCLIStatus(state: .notLoggedIn(host: "github.com"), hosts: loggedIn)
        }
        return GitHubCLIStatus(state: .ready(path: location.path, version: location.version), hosts: loggedIn)
    }

    func pullRequest(branch: String, in directory: URL) async -> FetchResult {
        guard let location = await locate(),
              let outcome = await run(location.path, PullRequestQuery.arguments(branch: branch), in: directory)
        else { return .failed(rateLimited: false) }
        guard outcome.succeeded else {
            let message = String(decoding: outcome.stderr, as: UTF8.self).lowercased()
            return .failed(rateLimited: message.contains("rate limit"))
        }
        do {
            return .found(try PullRequestQuery.parse(outcome.stdout))
        } catch {
            return .failed(rateLimited: false)
        }
    }

    func run(_ arguments: [String], in directory: URL?) async -> ProcessOutcome? {
        guard let location = await locate() else { return nil }
        return await run(location.path, arguments, in: directory)
    }

    nonisolated static func version(at path: String) async -> String? {
        guard FileManager.default.isExecutableFile(atPath: path),
              let outcome = await TimedProcess.run(path, ["--version"], timeout: .seconds(10)),
              outcome.succeeded else { return nil }
        return version(from: outcome)
    }

    nonisolated private static func version(from outcome: ProcessOutcome) -> String {
        outcome.output.firstMatch(of: #/gh version (\S+)/#).map { String($0.1) } ?? "?"
    }

    private func locate() async -> Location? {
        if let locating { return await locating.value }
        let task = Task { await search() }
        locating = task
        return await task.value
    }

    private func search() async -> Location? {
        var paths: [String] = []
        if let override { paths.append(override) }
        if let configured, !configured.isEmpty { paths.append(configured) }
        let variables = await shell.resolve().variables
        paths += (variables["PATH"] ?? "").split(separator: ":").map { "\($0)/gh" }
        paths += candidates
        for path in paths where FileManager.default.isExecutableFile(atPath: path) {
            if let outcome = await run(path, ["--version"], in: nil), outcome.succeeded {
                return Location(path: path, version: Self.version(from: outcome))
            }
        }
        return nil
    }

    private func isLoggedIn(_ host: String, with path: String) async -> Bool {
        if let known = logins[host] { return known }
        let loggedIn = await run(path, ["auth", "status", "--hostname", host], in: nil)?.succeeded == true
        logins[host] = loggedIn
        return loggedIn
    }

    private func run(_ path: String, _ arguments: [String], in directory: URL?) async -> ProcessOutcome? {
        var environment = await shell.resolve().variables
        environment.merge(Self.quiet) { $1 }
        return await runner(path, arguments, directory, environment, timeout)
    }
}
