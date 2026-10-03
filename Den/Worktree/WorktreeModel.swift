import Foundation
import Observation

@MainActor
@Observable
final class WorktreeModel {
    struct Draft: Equatable {
        var isEnabled: Bool
        var editedName: String?
        var chosen: Set<String>
    }

    enum Phase: Equatable {
        case creating(String)
        case failed(String)
    }

    static let enabledKey = "Den.worktreeDefault"
    static let prefixKey = "Den.branchPrefix"
    static let defaultPrefix = "den/"
    static let autoChooseLimit = 4

    private(set) var layouts: [String: WorktreeLayout] = [:]
    private(set) var phases: [UUID: Phase] = [:]
    private(set) var warnings: [UUID: String] = [:]
    private(set) var drafts: [UUID: Draft] = [:]
    private(set) var invalidNames: Set<String> = []
    private(set) var taken: [String: Set<String>] = [:]
    @ObservationIgnored private var cancelled: Set<UUID> = []

    @ObservationIgnored let ledger: TaskLedger
    @ObservationIgnored private let maker: WorktreeMaker
    @ObservationIgnored private let root: URL
    @ObservationIgnored private let defaults: UserDefaults

    init(ledger: TaskLedger, root: URL, defaults: UserDefaults, maker: WorktreeMaker = WorktreeMaker()) {
        self.ledger = ledger
        self.root = root
        self.defaults = defaults
        self.maker = maker
    }

    var prefix: String { defaults.string(forKey: Self.prefixKey) ?? Self.defaultPrefix }

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
        return Draft(isEnabled: defaults.bool(forKey: Self.enabledKey), editedName: nil,
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

    func rename(_ name: String, for chat: ChatModel) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let automatic = automaticName(for: chat, message: chat.prompt)
        update(chat) { $0.editedName = trimmed.isEmpty || trimmed == automatic ? nil : trimmed }
        guard let edited = draft(for: chat).editedName,
              let repo = chosenRepos(for: chat).first else { return }
        if await maker.isValidBranchName(edited, in: repo.main) {
            invalidNames.remove(edited)
        } else {
            invalidNames.insert(edited)
        }
    }

    func branchName(for chat: ChatModel, message: String) -> String {
        draft(for: chat).editedName ?? automaticName(for: chat, message: message)
    }

    func blocker(for chat: ChatModel) -> String? {
        guard isOffered(chat) else { return nil }
        let draft = draft(for: chat)
        guard draft.isEnabled else { return nil }
        if chosenRepos(for: chat).isEmpty { return "Escolha ao menos um repo" }
        guard let edited = draft.editedName else { return nil }
        if invalidNames.contains(edited) { return "Nome de branch inválido" }
        if let owner = owner(of: edited, for: chat) { return "Já existe em \(owner)" }
        if folderExists(edited, for: chat) { return "Já existe uma worktree com esse nome" }
        return nil
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
        let plan = WorktreePlanner.plan(layout: layout, sessionDirectory: chat.workingDirectory,
                                        chosen: draft(for: chat).chosen,
                                        branch: branchName(for: chat, message: text),
                                        prefix: prefix, root: root, entries: entries)
        phases[id] = .creating("Criando worktree…")
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

    private func automaticName(for chat: ChatModel, message: String) -> String {
        BranchNamer.name(for: message, prefix: prefix,
                         fallback: String(chat.sessionID.uuidString.lowercased().prefix(4))) { name in
            owner(of: name, for: chat) != nil || folderExists(name, for: chat)
        }
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
        let folder = BranchNamer.folder(for: name, prefix: prefix)
        return FileManager.default.fileExists(atPath: root.appending(path: group).appending(path: folder).path)
    }
}
