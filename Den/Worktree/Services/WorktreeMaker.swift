import Foundation

nonisolated struct WorktreeMaker: Sendable {
    typealias Git = @Sendable (_ arguments: [String], _ directory: URL,
                               _ timeout: Duration) async -> ProcessOutcome?

    enum Progress: Equatable, Sendable {
        case fetching(String)
        case creating(String)
        case linking
    }

    struct Failure: Error, Equatable, Sendable {
        let repo: String
        let message: String
    }

    struct Made: Equatable, Sendable {
        let worktree: TaskWorktree
        let warnings: [String]
    }

    private struct Created: Sendable {
        let repo: TaskWorktree.Repo
        let warning: String?
    }

    var git: Git = WorktreeMaker.systemGit
    var fetchTimeout: Duration = .seconds(30)
    var commandTimeout: Duration = .seconds(15)

    static let systemGit: Git = { arguments, directory, timeout in
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        if environment["GIT_SSH_COMMAND"] == nil {
            environment["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes"
        }
        return await TimedProcess.run("/usr/bin/git", ["-C", directory.path] + arguments,
                                      environment: environment, timeout: timeout)
    }

    func make(_ plan: WorktreePlan,
              progress: @escaping @Sendable (Progress) async -> Void = { _ in }) async throws -> Made {
        let folders = plan.mirrorRoot.map { [$0.lastPathComponent] }
            ?? plan.entries.map(\.worktree.lastPathComponent)
        guard folders.allSatisfy({ !["", ".", ".."].contains($0) }) else {
            throw Failure(repo: plan.branch, message: "nome de pasta inválido")
        }
        if let mirror = plan.mirrorRoot {
            do {
                try FileManager.default.createDirectory(at: mirror.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: mirror, withIntermediateDirectories: false)
            } catch {
                throw Failure(repo: mirror.lastPathComponent, message: "a pasta \(mirror.path) já existe")
            }
        }
        var results: [Int: Result<Created, Failure>] = [:]
        await withTaskGroup(of: (Int, Result<Created, Failure>).self) { group in
            for (index, entry) in plan.entries.enumerated() {
                group.addTask { (index, await create(entry, branch: plan.branch, progress: progress)) }
            }
            for await (index, result) in group { results[index] = result }
        }
        let ordered = plan.entries.indices.compactMap { results[$0] }
        let created = ordered.compactMap { try? $0.get() }
        for result in ordered {
            if case .failure(let failure) = result {
                await rollback(created.map(\.repo), branch: plan.branch, mirror: plan.mirrorRoot)
                throw failure
            }
        }
        if !plan.links.isEmpty {
            await progress(.linking)
            do {
                for link in plan.links {
                    try FileManager.default.createSymbolicLink(at: link.destination,
                                                               withDestinationURL: link.source)
                }
            } catch {
                await rollback(created.map(\.repo), branch: plan.branch, mirror: plan.mirrorRoot)
                throw Failure(repo: plan.mirrorRoot?.lastPathComponent ?? plan.branch,
                              message: error.localizedDescription)
            }
        }
        return Made(worktree: TaskWorktree(branch: plan.branch,
                                           sessionDirectory: plan.sessionDirectory,
                                           mirrorRoot: plan.mirrorRoot,
                                           repos: created.map(\.repo)),
                    warnings: created.compactMap(\.warning))
    }

    func undo(_ made: Made) async {
        await rollback(made.worktree.repos, branch: made.worktree.branch, mirror: made.worktree.mirrorRoot)
    }

    func takenNames(in repos: [URL]) async -> [URL: Set<String>] {
        var taken: [URL: Set<String>] = [:]
        for repo in repos {
            let listed = await git(["for-each-ref", "--format=%(refname)", "refs/heads", "refs/remotes"],
                                   repo, commandTimeout)?.output ?? ""
            taken[repo] = Set(listed.split(whereSeparator: \.isNewline).compactMap { line in
                let ref = String(line)
                if ref.hasPrefix("refs/heads/") { return String(ref.dropFirst("refs/heads/".count)) }
                let remote = ref.dropFirst("refs/remotes/".count)
                guard let slash = remote.firstIndex(of: "/") else { return nil }
                let name = String(remote[remote.index(after: slash)...])
                return name == "HEAD" ? nil : name
            })
        }
        return taken
    }

    private func create(_ entry: WorktreePlan.Entry, branch: String,
                        progress: @Sendable (Progress) async -> Void) async -> Result<Created, Failure> {
        let remotes = await git(["remote"], entry.main, commandTimeout)?.output
            .split(whereSeparator: \.isNewline).map(String.init) ?? []
        let remote = remotes.contains("origin") ? "origin" : remotes.first
        var fetched = false
        if let remote {
            await progress(.fetching(entry.name))
            fetched = await git(["fetch", "--no-tags", "--quiet", remote], entry.main,
                                fetchTimeout)?.succeeded == true
        }
        guard let base = await defaultBase(in: entry.main, remote: remote) else {
            return .failure(Failure(repo: entry.name, message: "não encontrei a branch padrão"))
        }
        await progress(.creating(entry.name))
        try? FileManager.default.createDirectory(at: entry.worktree.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        guard let added = await git(["worktree", "add", "--quiet", "--no-track", "-b", branch,
                                     entry.worktree.path, base], entry.main, commandTimeout) else {
            return .failure(Failure(repo: entry.name, message: "o git não respondeu"))
        }
        guard added.succeeded else {
            return .failure(Failure(repo: entry.name, message: added.errorLine))
        }
        var github: GitHubRemote?
        if let remote,
           let url = await git(["config", "--get", "remote.\(remote).url"], entry.main, commandTimeout),
           url.succeeded {
            github = GitHubRemote(remoteURL: url.output)
        }
        let warning = remote != nil && !fetched
            ? await offlineWarning(entry.name, base: base, in: entry.main) : nil
        return .success(Created(
            repo: TaskWorktree.Repo(name: entry.name, original: entry.main, worktree: entry.worktree,
                                    base: base, remote: github),
            warning: warning))
    }

    private func defaultBase(in repo: URL, remote: String?) async -> String? {
        if let remote,
           let head = await git(["symbolic-ref", "--quiet", "--short", "refs/remotes/\(remote)/HEAD"],
                                repo, commandTimeout),
           head.succeeded, !head.output.isEmpty {
            return head.output
        }
        let candidates = (remote.map { ["\($0)/main", "\($0)/master"] } ?? []) + ["main", "master"]
        for candidate in candidates {
            if await git(["rev-parse", "--verify", "--quiet", candidate + "^{commit}"], repo,
                         commandTimeout)?.succeeded == true {
                return candidate
            }
        }
        return nil
    }

    private func offlineWarning(_ name: String, base: String, in repo: URL) async -> String {
        var text = "Sem rede: \(name) partiu de \(base)"
        if let stamp = await git(["log", "-1", "--format=%ct", base], repo, commandTimeout)?.output,
           let seconds = TimeInterval(stamp) {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = Locale(identifier: "pt_BR")
            let age = formatter.localizedString(for: Date(timeIntervalSince1970: seconds), relativeTo: Date())
            text += " (último commit \(age))"
        }
        return text
    }

    private func rollback(_ repos: [TaskWorktree.Repo], branch: String, mirror: URL?) async {
        for repo in repos {
            _ = await git(["worktree", "remove", "--force", repo.worktree.path], repo.original,
                          commandTimeout)
            _ = await git(["branch", "-D", branch], repo.original, commandTimeout)
        }
        if let mirror { try? FileManager.default.removeItem(at: mirror) }
    }
}
