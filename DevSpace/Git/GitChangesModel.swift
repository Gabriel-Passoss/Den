import Foundation
import Observation

@MainActor
@Observable
final class GitChangesModel {
    nonisolated struct FileChange: Identifiable {
        let path: String
        let state: GitFileState
        let lines: [GitDisplayLine]
        let truncated: Bool
        let children: [String]
        let fingerprint: String

        var id: String { path }
        var isDirectory: Bool { path.hasSuffix("/") }
        var name: String {
            (String(path.hasSuffix("/") ? String(path.dropLast()) : path) as NSString)
                .lastPathComponent
        }
    }

    nonisolated struct Repo: Identifiable {
        let root: URL
        let branch: String?
        let files: [FileChange]
        let truncatedFiles: Bool

        var id: String { root.path }
        var name: String { root.lastPathComponent }
    }

    nonisolated private struct RepoSurvey {
        let root: URL
        let branch: String?
        let status: String
        let entries: [GitStatusEntry]
    }

    var repos: [Repo] = []
    var hasRepo = false
    var isLoading = false
    var loadedOnce = false

    private struct Snapshot {
        var repos: [Repo]
        var signature: String
        var hasRepo: Bool
    }

    private var cache: [URL: Snapshot] = [:]
    private var lastDirectory: URL?
    private var loadID = 0

    nonisolated private static let maxRepos = 10
    nonisolated private static let maxFilesPerRepo = 60
    nonisolated private static let maxLinesPerFile = 160

    var changeCount: Int {
        repos.reduce(0) { $0 + $1.files.count }
    }

    // MARK: - Revisão

    private var reviewed: Set<String> = []

    private func reviewKey(_ file: FileChange, in repo: Repo) -> String {
        repo.id + "|" + file.path + "|" + file.fingerprint
    }

    func isReviewed(_ file: FileChange, in repo: Repo) -> Bool {
        reviewed.contains(reviewKey(file, in: repo))
    }

    func setReviewed(_ flag: Bool, for file: FileChange, in repo: Repo) {
        if flag {
            reviewed.insert(reviewKey(file, in: repo))
        } else {
            reviewed.remove(reviewKey(file, in: repo))
        }
    }

    var reviewedCount: Int {
        repos.reduce(0) { total, repo in
            total + repo.files.count { isReviewed($0, in: repo) }
        }
    }

    #if DEBUG
    nonisolated private static let logStart = Date()
    private func trace(_ message: String) {
        guard ProcessInfo.processInfo.environment["DEVSPACE_GIT_LOG"] != nil else { return }
        let t = String(format: "%6.2f", Date().timeIntervalSince(Self.logStart))
        print("[git \(t)] \(message)")
    }
    #else
    private func trace(_: String) {}
    #endif

    func load(directory: URL, force: Bool = false) async {
        loadID += 1
        let id = loadID
        isLoading = true
        defer { if id == loadID { isLoading = false } }
        trace("start #\(id) \(directory.lastPathComponent) force=\(force)")

        if lastDirectory != directory {
            lastDirectory = directory
            if let cached = cache[directory] {
                trace("restore #\(id) \(directory.lastPathComponent) do cache")
                repos = cached.repos
                hasRepo = cached.hasRepo
                loadedOnce = true
            } else {
                trace("wipe #\(id) -> \(directory.lastPathComponent) (sem cache)")
                repos = []
                loadedOnce = false
            }
        }

        let began = Date()
        let roots = await Task.detached(priority: .userInitiated) {
            Self.discoverRepoRoots(under: directory)
        }.value
        guard id == loadID, !Task.isCancelled else { trace("abort #\(id)"); return }

        // Fase 1 — status de todos os repos em paralelo.
        var surveys = [RepoSurvey?](repeating: nil, count: roots.count)
        await withTaskGroup(of: (Int, RepoSurvey).self) { group in
            for (index, root) in roots.enumerated() {
                group.addTask {
                    await Task.detached(priority: .userInitiated) {
                        (index, await Self.survey(root))
                    }.value
                }
            }
            for await (index, survey) in group { surveys[index] = survey }
        }
        guard id == loadID, !Task.isCancelled else { trace("abort #\(id)"); return }

        let statuses = surveys.compactMap { $0 }
        let newSignature = statuses
            .map { "\($0.root.path)@\($0.branch ?? "")\n\($0.status)\n" }
            .joined()
        trace("status #\(id) \(directory.lastPathComponent): \(roots.count) repos em \(String(format: "%.2f", Date().timeIntervalSince(began)))s")

        hasRepo = !roots.isEmpty
        if !force, newSignature == cache[directory]?.signature {
            trace("keep #\(id) \(directory.lastPathComponent) (assinatura igual)")
            repos = cache[directory]?.repos ?? repos
            loadedOnce = true
            return
        }

        // Fase 2 — diff + realce de cada repo em paralelo, fora da main thread.
        var built = [Repo?](repeating: nil, count: statuses.count)
        await withTaskGroup(of: (Int, Repo).self) { group in
            for (index, survey) in statuses.enumerated() {
                group.addTask {
                    await Task.detached(priority: .userInitiated) {
                        (index, await Self.assembleRepo(survey))
                    }.value
                }
            }
            for await (index, repo) in group { built[index] = repo }
        }
        guard id == loadID, !Task.isCancelled else { trace("abort #\(id)"); return }
        let newRepos = built.compactMap { $0 }

        trace("commit #\(id) \(directory.lastPathComponent): \(newRepos.count) repos, \(newRepos.reduce(0) { $0 + $1.files.count }) arquivos em \(String(format: "%.2f", Date().timeIntervalSince(began)))s")
        repos = newRepos
        cache[directory] = Snapshot(repos: newRepos, signature: newSignature,
                                    hasRepo: !roots.isEmpty)
        loadedOnce = true

        let valid = Set(cache.values.flatMap { snapshot in
            snapshot.repos.flatMap { repo in
                repo.files.map { reviewKey($0, in: repo) }
            }
        })
        reviewed.formIntersection(valid)
    }

    nonisolated private static func survey(_ root: URL) async -> RepoSurvey {
        async let branchOut = GitCommand.run(["rev-parse", "--abbrev-ref", "HEAD"], in: root)
        async let statusOut = GitCommand.run(["status", "--porcelain=v1", "-z"], in: root)
        let branch = (await branchOut)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = await statusOut ?? ""
        return RepoSurvey(root: root, branch: branch, status: status,
                          entries: GitParsing.statusEntries(fromPorcelain: status))
    }

    nonisolated private static func assembleRepo(_ survey: RepoSurvey) async -> Repo {
        let root = survey.root
        let entries = survey.entries

        var diffs: [String: [GitDiffLine]] = [:]
        if entries.contains(where: { $0.state != .untracked }) {
            var output = await GitCommand.run(
                ["diff", "HEAD", "--no-color", "--no-ext-diff", "--unified=2"], in: root)
            if output == nil {
                output = await GitCommand.run(
                    ["diff", "--no-color", "--no-ext-diff", "--unified=2"], in: root)
            }
            diffs = GitParsing.fileDiffs(fromUnified: String((output ?? "").prefix(400_000)))
        }

        let ordered = entries.sorted {
            ($0.isDirectory ? 0 : 1, $0.path) < ($1.isDirectory ? 0 : 1, $1.path)
        }

        var files: [FileChange] = []
        for entry in ordered.prefix(maxFilesPerRepo) {
            if Task.isCancelled { break }
            let target = root.appending(path: entry.path)
            var lines: [GitDiffLine] = []
            var children: [String] = []

            if entry.isDirectory {
                children = listChildren(of: target)
            } else if entry.state == .untracked {
                lines = untrackedLines(of: target)
            } else {
                lines = diffs[entry.path] ?? []
            }

            let truncated = lines.count > maxLinesPerFile
            let capped = Array(lines.prefix(maxLinesPerFile))
            let language = SyntaxHighlighter.language(forFile: entry.path)
            files.append(FileChange(
                path: entry.path,
                state: entry.state,
                lines: SyntaxHighlighter.render(capped, language: language),
                truncated: truncated,
                children: children,
                fingerprint: GitParsing.fingerprint(
                    of: [entry.state.badge] + capped.map(\.text) + children)))
        }

        return Repo(root: root, branch: survey.branch, files: files,
                    truncatedFiles: entries.count > maxFilesPerRepo)
    }

    // MARK: - Trabalho fora da main thread

    nonisolated private static let skippedFolders: Set<String> = [
        "node_modules", ".build", "DerivedData", ".next", "dist", "build",
        "Pods", ".venv", "vendor",
    ]

    nonisolated static func discoverRepoRoots(under directory: URL) -> [URL] {
        let manager = FileManager.default
        var roots: [URL] = []

        var toplevel: URL?
        var probe = directory.standardizedFileURL
        while probe.pathComponents.count > 1 {
            if manager.fileExists(atPath: probe.appending(path: ".git").path) {
                toplevel = probe
                break
            }
            probe = probe.deletingLastPathComponent()
        }
        if let toplevel { roots.append(toplevel) }

        func scan(_ dir: URL, depth: Int) {
            guard roots.count < maxRepos,
                  let children = try? manager.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]) else { return }
            for child in children.sorted(by: { $0.path < $1.path }) {
                guard (try? child.resourceValues(forKeys: [.isDirectoryKey]))?
                    .isDirectory == true,
                      !skippedFolders.contains(child.lastPathComponent)
                else { continue }
                if manager.fileExists(atPath: child.appending(path: ".git").path) {
                    if roots.count < maxRepos { roots.append(child.standardizedFileURL) }
                } else if depth < 2 {
                    scan(child, depth: depth + 1)
                }
            }
        }
        scan(directory.standardizedFileURL, depth: 1)

        var seen: Set<String> = []
        return roots.filter { seen.insert($0.path).inserted }
    }

    nonisolated static func listChildren(of directory: URL, cap: Int = 30) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path))
            ?? []
        return names.sorted().prefix(cap).map { $0 }
    }

    nonisolated static func untrackedLines(of file: URL, cap: Int = 200) -> [GitDiffLine] {
        guard let handle = try? FileHandle(forReadingFrom: file),
              let data = try? handle.read(upToCount: 96 * 1024) else { return [] }
        try? handle.close()

        if data.contains(0) {
            return [GitDiffLine(id: 0, kind: .hunk, number: nil, text: "Arquivo binário")]
        }
        let text = String(decoding: data, as: UTF8.self)
        return text.components(separatedBy: "\n").prefix(cap).enumerated()
            .map { index, line in
                GitDiffLine(id: index, kind: .added, number: index + 1, text: line)
            }
    }
}
