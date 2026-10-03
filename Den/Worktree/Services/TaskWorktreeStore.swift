import Foundation

nonisolated struct TaskWorktreeStore: Sendable {
    let url: URL

    struct Entry: Codable, Equatable, Sendable {
        var worktree: TaskWorktree
        var pullRequests: [String: PullRequest]
        var dismissed: [String: String]

        init(worktree: TaskWorktree, pullRequests: [String: PullRequest] = [:],
             dismissed: [String: String] = [:]) {
            self.worktree = worktree
            self.pullRequests = pullRequests
            self.dismissed = dismissed
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            worktree = try container.decode(TaskWorktree.self, forKey: .worktree)
            pullRequests = try container.decodeIfPresent([String: PullRequest].self, forKey: .pullRequests) ?? [:]
            dismissed = try container.decodeIfPresent([String: String].self, forKey: .dismissed) ?? [:]
        }
    }

    private struct File: Codable {
        var version: Int
        var sessions: [String: Entry]
    }

    func load() -> [UUID: Entry] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        do {
            let sessions = try JSONDecoder().decode(File.self, from: data).sessions
            return Dictionary(uniqueKeysWithValues: sessions.compactMap { key, entry in
                UUID(uuidString: key).map { ($0, entry) }
            })
        } catch {
            UnreadableFile.setAside(url, holding: "worktrees de tarefa", because: error)
            return [:]
        }
    }

    func save(_ entries: [UUID: Entry]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let file = File(version: 1, sessions: Dictionary(uniqueKeysWithValues: entries.map {
            ($0.key.uuidString, $0.value)
        }))
        try encoder.encode(file).write(to: url, options: .atomic)
    }
}
