import Foundation

nonisolated enum WorktreePlanner {
    static func plan(layout: WorktreeLayout, sessionDirectory: URL, chosen: Set<String>,
                     branch: String, prefix: String, root: URL, entries: [URL]) -> WorktreePlan {
        let folder = BranchNamer.folder(for: branch, prefix: prefix)
        switch layout {
        case .single(let repo):
            let worktree = root.appending(path: repo.name).appending(path: folder)
            let relative = relativePath(of: sessionDirectory, under: repo.toplevel)
            return WorktreePlan(
                branch: branch,
                sessionDirectory: relative.isEmpty ? worktree : worktree.appending(path: relative),
                mirrorRoot: nil,
                entries: [.init(name: repo.name, main: repo.main, worktree: worktree)],
                links: [])
        case .multiple(let base, let repos):
            let mirror = root.appending(path: group(for: base, root: root)).appending(path: folder)
            let planned = repos.filter { chosen.contains($0.id) }.map { repo in
                WorktreePlan.Entry(name: repo.name, main: repo.main,
                                   worktree: mirror.appending(path: relativePath(of: repo.toplevel, under: base)))
            }
            let links = entries.map(\.standardizedFileURL).filter { entry in
                let name = entry.lastPathComponent
                guard name != ".DS_Store", !ProjectScan.skippedFolders.contains(name) else { return false }
                return !repos.contains { repo in
                    repo.toplevel.path == entry.path || repo.toplevel.path.hasPrefix(entry.path + "/")
                }
            }.map { entry in
                WorktreePlan.Link(source: entry.resolvingSymlinksInPath(),
                                  destination: mirror.appending(path: entry.lastPathComponent))
            }
            return WorktreePlan(branch: branch, sessionDirectory: mirror, mirrorRoot: mirror,
                                entries: planned, links: links)
        }
    }

    static func group(for folder: URL, root: URL) -> String {
        let path = folder.standardizedFileURL.path
        let base = root.standardizedFileURL.path + "/"
        if path.hasPrefix(base), let first = path.dropFirst(base.count).split(separator: "/").first {
            return String(first)
        }
        return folder.lastPathComponent
    }

    private static func relativePath(of url: URL, under base: URL) -> String {
        let path = url.standardizedFileURL.path
        let prefix = base.standardizedFileURL.path
        guard path.hasPrefix(prefix + "/") else { return "" }
        return String(path.dropFirst(prefix.count + 1))
    }
}
