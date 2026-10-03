import Foundation

nonisolated enum WorktreeLocator {
    static func current(_ task: TaskWorktree) -> TaskWorktree {
        var current = task
        var branch: String?
        for index in task.repos.indices {
            let repo = task.repos[index]
            guard let admin = gitDirectory(of: repo), let folder = worktree(of: admin) else { continue }
            current.repos[index].gitDirectory = admin
            if !same(folder, repo.worktree) {
                current.repos[index].worktree = folder
                if let inside = path(of: task.sessionDirectory, inside: repo.worktree) {
                    current.sessionDirectory = inside.isEmpty ? folder : folder.appending(path: inside)
                }
            }
            if branch == nil { branch = self.branch(of: admin) }
        }
        if let branch { current.branch = branch }
        return current
    }

    static func gitDirectory(ofWorktreeAt folder: URL) -> URL? {
        let marker = folder.appending(path: ".git")
        guard !marker.isExistingDirectory,
              let text = try? String(contentsOf: marker, encoding: .utf8),
              let line = text.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("gitdir:") })
        else { return nil }
        let admin = url(line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces),
                        relativeTo: folder)
        return isGitDirectory(admin) ? admin : nil
    }

    private static func gitDirectory(of repo: TaskWorktree.Repo) -> URL? {
        if let recorded = repo.gitDirectory, isGitDirectory(recorded) { return recorded }
        if let found = gitDirectory(ofWorktreeAt: repo.worktree) { return found }
        let guess = GitRepository.mainCheckout(of: repo.original)
            .appending(path: ".git/worktrees")
            .appending(path: repo.worktree.lastPathComponent)
        return isGitDirectory(guess) ? guess : nil
    }

    private static func isGitDirectory(_ admin: URL) -> Bool {
        FileManager.default.fileExists(atPath: admin.appending(path: "gitdir").path)
    }

    private static func worktree(of admin: URL) -> URL? {
        guard let text = try? String(contentsOf: admin.appending(path: "gitdir"), encoding: .utf8)
        else { return nil }
        let marker = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !marker.isEmpty else { return nil }
        return url(marker, relativeTo: admin).deletingLastPathComponent()
    }

    private static func branch(of admin: URL) -> String? {
        guard let text = try? String(contentsOf: admin.appending(path: "HEAD"), encoding: .utf8)
        else { return nil }
        let head = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "ref: refs/heads/"
        guard head.hasPrefix(prefix), head.count > prefix.count else { return nil }
        return String(head.dropFirst(prefix.count))
    }

    private static func url(_ path: String, relativeTo base: URL) -> URL {
        (path.hasPrefix("/") ? URL(fileURLWithPath: path) : base.appending(path: path)).standardizedFileURL
    }

    private static func same(_ one: URL, _ other: URL) -> Bool {
        one.resolvingSymlinksInPath().path == other.resolvingSymlinksInPath().path
    }

    private static func path(of folder: URL, inside parent: URL) -> String? {
        let child = folder.standardizedFileURL.path
        let root = parent.standardizedFileURL.path
        if child == root { return "" }
        guard child.hasPrefix(root + "/") else { return nil }
        return String(child.dropFirst(root.count + 1))
    }
}
