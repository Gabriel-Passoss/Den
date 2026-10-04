import Foundation
import Observation
import DenStore

@MainActor
@Observable
final class TaskLedger {
    private(set) var entries: [UUID: TaskWorktreeEntry]
    @ObservationIgnored private let repository: any SessionDocumentRepository<TaskWorktreeEntry>

    init(repository: any SessionDocumentRepository<TaskWorktreeEntry>) {
        self.repository = repository
        self.entries = repository.all()
    }

    func worktree(for id: UUID) -> TaskWorktree? { entries[id]?.worktree }

    func record(_ worktree: TaskWorktree, for id: UUID) {
        entries[id] = TaskWorktreeEntry(worktree: worktree)
        persist(id)
    }

    func update(_ worktree: TaskWorktree, for id: UUID) {
        guard var entry = entries[id], entry.worktree != worktree else { return }
        var pullRequests: [String: PullRequest] = [:]
        var dismissed: [String: String] = [:]
        for (old, new) in zip(entry.worktree.repos, worktree.repos) {
            pullRequests[new.worktree.path] = entry.pullRequests[old.worktree.path]
            dismissed[new.worktree.path] = entry.dismissed[old.worktree.path]
        }
        entry.worktree = worktree
        entry.pullRequests = pullRequests
        entry.dismissed = dismissed
        entries[id] = entry
        persist(id)
    }

    func forget(_ id: UUID) {
        guard entries.removeValue(forKey: id) != nil else { return }
        persist(id)
    }

    func pullRequests(for id: UUID) -> [String: PullRequest] {
        entries[id]?.pullRequests ?? [:]
    }

    func setPullRequest(_ pr: PullRequest?, for id: UUID, worktree path: String) {
        guard var entry = entries[id], entry.pullRequests[path] != pr else { return }
        entry.pullRequests[path] = pr
        entries[id] = entry
        persist(id)
    }

    func dismissedSignature(for id: UUID, worktree path: String) -> String? {
        entries[id]?.dismissed[path]
    }

    func dismiss(_ id: UUID, worktree path: String, signature: String) {
        guard var entry = entries[id] else { return }
        entry.dismissed[path] = signature
        entries[id] = entry
        persist(id)
    }

    private func persist(_ id: UUID) {
        do {
            if let entry = entries[id] {
                try repository.save(entry, for: id)
            } else {
                try repository.remove(id)
            }
        } catch {
            print("não consegui gravar a worktree de tarefa: \(error)")
        }
    }
}
