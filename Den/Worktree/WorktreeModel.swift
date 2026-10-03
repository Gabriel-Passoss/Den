import Foundation
import Observation
import HarnessCore

@MainActor
@Observable
final class WorktreeModel {
    struct Draft: Equatable {
        var isEnabled: Bool
        var chosen: Set<String>
    }

    enum Phase: Equatable {
        case creating(String)
        case failed(String)
    }

    static let enabledKey = "Den.worktreeDefault"
    static let autoChooseLimit = 4

    private(set) var layouts: [String: WorktreeLayout] = [:]
    private(set) var phases: [UUID: Phase] = [:]
    private(set) var warnings: [UUID: String] = [:]
    private(set) var drafts: [UUID: Draft] = [:]
    private(set) var taken: [String: Set<String>] = [:]
    @ObservationIgnored private var cancelled: Set<UUID> = []

    @ObservationIgnored let ledger: TaskLedger
    @ObservationIgnored private let maker: WorktreeMaker
    @ObservationIgnored private let root: URL
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let registry: HarnessRegistry
    @ObservationIgnored private let suggester: BranchSuggester

    init(ledger: TaskLedger, root: URL, defaults: UserDefaults, maker: WorktreeMaker = WorktreeMaker(),
         registry: HarnessRegistry = .standard, suggester: BranchSuggester = BranchSuggester()) {
        self.ledger = ledger
        self.root = root
        self.defaults = defaults
        self.maker = maker
        self.registry = registry
        self.suggester = suggester
    }

    func worktree(for id: UUID) -> TaskWorktree? { ledger.worktree(for: id) }

    func layout(for chat: ChatModel) -> WorktreeLayout? {
        layouts[chat.workingDirectory.standardizedFileURL.path]
    }

    func phase(for id: UUID) -> Phase? { phases[id] }

    func isCreating(_ id: UUID) -> Bool {
        if case .creating = phases[id] { return true }
        return false
    }

    func isOffered(_ chat: ChatModel) -> Bool {
        worktree(for: chat.sessionID) == nil
            && layout(for: chat) != nil
            && !chat.lines.contains { $0.role == .user }
    }

    func prepare(_ chat: ChatModel) async {
        let directory = chat.workingDirectory.standardizedFileURL
        let key = directory.path
        if layouts[key] == nil {
            guard let detected = await Task.detached(operation: { WorktreeLayout.detect(directory) }).value
            else { return }
            layouts[key] = detected
        }
        guard let layout = layouts[key] else { return }
        let names = await maker.takenNames(in: layout.repos.map(\.main))
        for (repo, branches) in names { taken[repo.standardizedFileURL.path] = branches }
    }

    func draft(for chat: ChatModel) -> Draft {
        if let draft = drafts[chat.sessionID] { return draft }
        let repos = layout(for: chat)?.repos ?? []
        return Draft(isEnabled: defaults.bool(forKey: Self.enabledKey),
                     chosen: repos.count <= Self.autoChooseLimit ? Set(repos.map(\.id)) : [])
    }

    func setEnabled(_ enabled: Bool, for chat: ChatModel) {
        guard !isCreating(chat.sessionID) else { return }
        update(chat) { $0.isEnabled = enabled }
        defaults.set(enabled, forKey: Self.enabledKey)
        if !enabled { phases[chat.sessionID] = nil }
    }

    func toggle(repo id: String, for chat: ChatModel) {
        update(chat) { draft in
            if draft.chosen.contains(id) { draft.chosen.remove(id) } else { draft.chosen.insert(id) }
        }
    }

    func blocker(for chat: ChatModel) -> String? {
        guard isOffered(chat), draft(for: chat).isEnabled else { return nil }
        return chosenRepos(for: chat).isEmpty ? "Escolha ao menos um repo" : nil
    }

    func canSend(_ chat: ChatModel) -> Bool {
        !isCreating(chat.sessionID) && blocker(for: chat) == nil
    }

    func launch(_ chat: ChatModel, text: String) async {
        let id = chat.sessionID
        guard !isCreating(id) else {
            chat.prompt = text
            return
        }
        phases[id] = nil
        guard isOffered(chat), draft(for: chat).isEnabled, let layout = layout(for: chat) else {
            await chat.send(text: text)
            return
        }
        guard canSend(chat) else {
            chat.prompt = text
            return
        }
        var entries: [URL] = []
        if case .multiple = layout {
            entries = (try? FileManager.default.contentsOfDirectory(
                at: chat.workingDirectory, includingPropertiesForKeys: nil)) ?? []
        }
        phases[id] = .creating("Criando worktree · escolhendo o nome…")
        let suggestion = await suggestion(for: chat, text: text)
        if cancelled.remove(id) != nil { return }
        let branch = BranchNamer.name(stem: suggestion.stem, prefix: suggestion.type + "/") { name in
            owner(of: name, for: chat) != nil || folderExists(name, for: chat)
        }
        let plan = WorktreePlanner.plan(layout: layout, sessionDirectory: chat.workingDirectory,
                                        chosen: draft(for: chat).chosen, branch: branch,
                                        prefix: "", root: root, entries: entries)
        do {
            let made = try await maker.make(plan) { [weak self] progress in
                await self?.show(progress, for: id)
            }
            if cancelled.remove(id) != nil {
                await maker.undo(made)
                return
            }
            ledger.record(made.worktree, for: id)
            phases[id] = nil
            drafts[id] = nil
            warnings[id] = made.warnings.first
            await chat.choose(directory: made.worktree.sessionDirectory)
            await chat.send(text: text)
        } catch let failure as WorktreeMaker.Failure {
            guard cancelled.remove(id) == nil else { return }
            phases[id] = .failed("Falhou em \(failure.repo): \(failure.message)")
            chat.prompt = text
        } catch {
            guard cancelled.remove(id) == nil else { return }
            phases[id] = .failed("Falhou: \(error.localizedDescription)")
            chat.prompt = text
        }
    }

    func clearWarning(_ id: UUID) { warnings[id] = nil }

    func forget(_ id: UUID) {
        if isCreating(id) { cancelled.insert(id) }
        ledger.forget(id)
        drafts[id] = nil
        phases[id] = nil
        warnings[id] = nil
    }

    private func show(_ progress: WorktreeMaker.Progress, for id: UUID) {
        guard !cancelled.contains(id) else { return }
        switch progress {
        case .fetching(let repo): phases[id] = .creating("Criando worktree · buscando \(repo)…")
        case .creating(let repo): phases[id] = .creating("Criando worktree · criando \(repo)…")
        case .linking: phases[id] = .creating("Criando worktree · ligando os arquivos da pasta…")
        }
    }

    private func suggestion(for chat: ChatModel, text: String) async -> BranchSuggestion {
        if let harness = registry.harness(for: chat.harness),
           let suggested = await suggester.suggest(for: text, harness: harness) {
            return suggested
        }
        return BranchSuggestion(
            type: BranchNamer.type(for: text),
            stem: BranchNamer.stem(for: text)
                ?? "\(BranchNamer.fallbackStem)-\(chat.sessionID.uuidString.lowercased().prefix(4))")
    }

    private func update(_ chat: ChatModel, _ change: (inout Draft) -> Void) {
        var draft = draft(for: chat)
        change(&draft)
        drafts[chat.sessionID] = draft
    }

    private func chosenRepos(for chat: ChatModel) -> [RepoCandidate] {
        switch layout(for: chat) {
        case .single(let repo):
            return [repo]
        case .multiple(_, let repos):
            let chosen = draft(for: chat).chosen
            return repos.filter { chosen.contains($0.id) }
        case nil:
            return []
        }
    }

    private func owner(of name: String, for chat: ChatModel) -> String? {
        chosenRepos(for: chat).first { taken[$0.main.path]?.contains(name) == true }?.name
    }

    private func folderExists(_ name: String, for chat: ChatModel) -> Bool {
        let group: String
        switch layout(for: chat) {
        case .single(let repo): group = repo.name
        case .multiple(let base, _): group = WorktreePlanner.group(for: base, root: root)
        case nil: return false
        }
        let folder = BranchNamer.folder(for: name, prefix: "")
        return FileManager.default.fileExists(atPath: root.appending(path: group).appending(path: folder).path)
    }
}
