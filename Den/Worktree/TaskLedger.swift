import Foundation
import Observation

@MainActor
@Observable
final class TaskLedger {
    private(set) var entries: [UUID: TaskWorktreeStore.Entry]
    @ObservationIgnored private let store: TaskWorktreeStore

    init(store: TaskWorktreeStore) {
        self.store = store
        self.entries = store.load()
    }

    func worktree(for id: UUID) -> TaskWorktree? { entries[id]?.worktree }

    func record(_ worktree: TaskWorktree, for id: UUID) {
        entries[id] = TaskWorktreeStore.Entry(worktree: worktree)
        persist()
    }

    func forget(_ id: UUID) {
        guard entries.removeValue(forKey: id) != nil else { return }
        persist()
    }

    func pullRequests(for id: UUID) -> [String: PullRequest] {
        entries[id]?.pullRequests ?? [:]
    }

    func setPullRequest(_ pr: PullRequest?, for id: UUID, worktree path: String) {
        guard var entry = entries[id], entry.pullRequests[path] != pr else { return }
        entry.pullRequests[path] = pr
        entries[id] = entry
        persist()
    }

    func dismissedSignature(for id: UUID, worktree path: String) -> String? {
        entries[id]?.dismissed[path]
    }

    func dismiss(_ id: UUID, worktree path: String, signature: String) {
        guard var entry = entries[id] else { return }
        entry.dismissed[path] = signature
        entries[id] = entry
        persist()
    }

    private func persist() {
        do {
            try store.save(entries)
        } catch {
            print("não consegui gravar as worktrees de tarefa: \(error)")
        }
    }
}
