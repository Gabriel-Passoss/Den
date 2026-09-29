import Foundation
import Observation

@Observable final class MentionController {
    var fileIndex: [MentionCandidate] = []
    var selection = 0
    var dismissed = false

    func query(in text: String) -> String? {
                guard let at = text.range(of: "@", options: .backwards) else { return nil }
        let token = text[at.upperBound...]
        guard !token.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
        if at.lowerBound > text.startIndex {
            let previous = text[text.index(before: at.lowerBound)]
            guard previous.isWhitespace || previous.isNewline else { return nil }
        }
        return String(token)
    }

    func matches(prompt: String) -> [MentionCandidate] {
        guard !dismissed, let query = query(in: prompt) else { return [] }
        guard !query.isEmpty else { return Array(fileIndex.prefix(8)) }
        let needle = Array(MentionCandidate.searchable(query).utf8)
        // Best rank first, index order within a rank. Eight hits of the best
        // rank are the answer, so the walk stops there.
        var ranks: [[MentionCandidate]] = [[], [], []]
        for candidate in fileIndex {
            guard let rank = candidate.rank(for: needle), ranks[rank].count < 8 else { continue }
            ranks[rank].append(candidate)
            if ranks[0].count == 8 { break }
        }
        return Array(ranks.joined().prefix(8))
    }

    func accept(_ candidate: MentionCandidate, in chat: ChatModel) {
        guard let at = chat.prompt.range(of: "@", options: .backwards) else { return }
        let prefix = String(chat.prompt[..<at.lowerBound])
        if candidate.isDirectory {
            chat.prompt = prefix + "@" + candidate.path + "/"
        } else {
            chat.prompt = prefix + "@" + candidate.path + " "
        }
    }

    func loadIndex(under root: URL) async {
        let root = root
        fileIndex = await Task.detached(priority: .utility) {
            Self.indexFiles(under: root)
        }.value
    }

    /// Walks one level at a time, so when the limit cuts in it drops the
    /// deepest entries. A depth-first walk spent it all inside the first big
    /// folder and never reached the ones beside it. Build output and extra
    /// checkouts of a repo stay out, so the limit goes to sources.
    nonisolated static func indexFiles(under root: URL, limit: Int = 25_000) -> [MentionCandidate] {
        let skip: Set<String> = ["node_modules", ".git", ".build", "DerivedData",
                                 ".next", "dist", "build", "Pods", ".venv", "vendor",
                                 "target", ".gradle", "out", "coverage"]
        let base = canonical(root)
        var results: [MentionCandidate] = []
        var folders: [(url: URL, path: String)] = [(base, "")]
        var next = 0
        while next < folders.count, results.count < limit {
            let folder = folders[next]
            next += 1
            let children = (try? FileManager.default.contentsOfDirectory(
                at: folder.url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])) ?? []
            for url in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                if results.count >= limit { break }
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?
                    .isDirectory ?? false
                if isDirectory, skip.contains(url.lastPathComponent)
                    || isWorktree(url, ofARepoUnder: base) { continue }
                let path = folder.path + url.lastPathComponent
                results.append(MentionCandidate(path: path, isDirectory: isDirectory))
                if isDirectory { folders.append((url, path + "/")) }
            }
        }
        return results.sorted {
            let a = $0.path.filter { $0 == "/" }.count
            let b = $1.path.filter { $0 == "/" }.count
            return a == b ? $0.path < $1.path : a < b
        }
    }

    nonisolated private static func canonical(_ root: URL) -> URL {
        let resolved = root.resolvingSymlinksInPath()
        guard let path = try? resolved.resourceValues(forKeys: [.canonicalPathKey])
            .canonicalPath else { return resolved }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Whether `folder` is a `git worktree` of a repo inside `root`: the same
    /// sources again on another branch. Its `.git` file points into the repo's
    /// `.git/worktrees`; a submodule's points into `.git/modules` and stays.
    nonisolated private static func isWorktree(_ folder: URL, ofARepoUnder root: URL) -> Bool {
        let marker = folder.appending(path: ".git")
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: marker.path, isDirectory: &isFolder),
              !isFolder.boolValue,
              let text = try? String(contentsOf: marker, encoding: .utf8),
              let line = text.split(separator: "\n").first, line.hasPrefix("gitdir: ")
        else { return false }
        let target = String(line.dropFirst("gitdir: ".count))
        let gitdir = target.hasPrefix("/") ? URL(fileURLWithPath: target)
                                           : folder.appending(path: target)
        let resolved = gitdir.standardizedFileURL.path
        guard let marked = resolved.range(of: "/.git/worktrees/") else { return false }
        let repo = canonical(URL(fileURLWithPath: String(resolved[..<marked.lowerBound]))).path
        return repo == root.path || repo.hasPrefix(root.path + "/")
    }
}
