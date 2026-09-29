import AppKit
import Foundation
import Observation
import HarnessCore

@MainActor
@Observable
final class WorkspaceModel {
    var summaries: [SessionSummary] = []
    var selectedID: UUID?
    var search: String = ""

    var workingDirectory: URL = URL(fileURLWithPath: NSHomeDirectory())

    struct Folder: Identifiable, Codable, Equatable {
        let id: String
        var name: String
    }

    var folders: [Folder] = [] {
        didSet { persistFolders(folders) }
    }

    var membership: [String: String] = [:] {
        didSet { defaults.set(membership, forKey: Self.membershipKey) }
    }

    var sessionOrder: [String] = [] {
        didSet { defaults.set(sessionOrder, forKey: Self.orderKey) }
    }

    var defaultHarness: HarnessID {
        get { registry.preferred(in: defaults) }
        set { registry.setPreferred(newValue, in: defaults) }
    }

    var availableHarnesses: [HarnessID] { registry.ids }

    private let store: FileTranscriptStore
    private let defaults: UserDefaults
    private let cache: SessionCache
    private let registry: HarnessRegistry
    private let attachmentsRoot: URL
    private var chats: [UUID: ChatModel] = [:]
    private var legacyPathToFolder: [String: String] = [:]

    private static let foldersKey = "DevSpace.folders.v2"
    private static let membershipKey = "DevSpace.sessionFolders"
    private static let orderKey = "DevSpace.sessionOrder"
    private static let legacyFoldersKey = "DevSpace.folders"
    private static let legacyNamesKey = "DevSpace.folderNames"

    static func live(_ environment: LaunchEnvironment = .current) -> WorkspaceModel {
        let root = environment.sessionsRoot
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let workspace = WorkspaceModel(store: FileTranscriptStore(root: root),
                                       defaults: environment.defaults,
                                       cache: SessionCache(defaults: environment.defaults),
                                       registry: environment.registry,
                                       attachmentsRoot: environment.attachmentsRoot)
        workspace.workingDirectory = environment.workingDirectory
        return workspace
    }

    init(store: FileTranscriptStore, defaults: UserDefaults, cache: SessionCache,
         registry: HarnessRegistry = .standard,
         attachmentsRoot: URL = ChatModel.standardAttachmentsRoot) {
        self.store = store
        self.defaults = defaults
        self.cache = cache
        self.registry = registry
        self.attachmentsRoot = attachmentsRoot

        if let data = defaults.data(forKey: Self.foldersKey),
           let decoded = try? JSONDecoder().decode([Folder].self, from: data) {
            self.folders = decoded
        } else {
            let paths = defaults.array(forKey: Self.legacyFoldersKey) as? [String] ?? []
            let names = defaults.dictionary(forKey: Self.legacyNamesKey) as? [String: String] ?? [:]
            var migrated: [Folder] = []
            for path in paths {
                let folder = Folder(
                    id: UUID().uuidString,
                    name: names[path] ?? URL(fileURLWithPath: path).lastPathComponent)
                migrated.append(folder)
                legacyPathToFolder[path] = folder.id
            }
            self.folders = migrated
            persistFolders(migrated)
        }
        self.membership = defaults.dictionary(forKey: Self.membershipKey) as? [String: String] ?? [:]
        self.sessionOrder = defaults.array(forKey: Self.orderKey) as? [String] ?? []
    }

    func renameFolder(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].name = trimmed
    }

    func renameSession(_ id: UUID, to title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var session = try? await store.load(id) else { return }
        session.title = trimmed
        try? await store.saveMetadata(session)
        chats[id]?.adoptTitle(trimmed)
        await refresh()
    }

    func moveSession(_ id: UUID, toFolder folderID: String?) {
        membership[id.uuidString] = folderID
    }

    private func ordered(_ sessions: [SessionSummary]) -> [SessionSummary] {
        let index = Dictionary(uniqueKeysWithValues:
            sessionOrder.enumerated().map { ($1, $0) })
        return sessions.sorted { a, b in
            switch (index[a.id.uuidString], index[b.id.uuidString]) {
            case let (ia?, ib?): ia < ib
            case (.some, nil): false
            case (nil, .some): true
            case (nil, nil): a.updatedAt > b.updatedAt
            }
        }
    }

    private func fullOrderSnapshot() -> [String] {
        let valid = Set(folders.map(\.id))
        let byFolder = Dictionary(grouping: summaries) { membership[$0.id.uuidString] ?? "" }
        var order: [String] = []
        for folder in folders {
            order += ordered(byFolder[folder.id] ?? []).map(\.id.uuidString)
        }
        let loose = summaries.filter { summary in
            guard let folderID = membership[summary.id.uuidString] else { return true }
            return !valid.contains(folderID)
        }
        order += ordered(loose).map(\.id.uuidString)
        return order
    }

    func placeSession(_ id: UUID, near targetID: UUID) {
        guard id != targetID else { return }
        var order = fullOrderSnapshot()
        guard let from = order.firstIndex(of: id.uuidString),
              let to = order.firstIndex(of: targetID.uuidString) else { return }
        let moved = order.remove(at: from)
        order.insert(moved, at: to)
        membership[id.uuidString] = membership[targetID.uuidString]
        sessionOrder = order
    }

    func moveFolder(_ id: String, before targetID: String?) {
        guard id != targetID,
              let from = folders.firstIndex(where: { $0.id == id }) else { return }
        let folder = folders.remove(at: from)
        if let targetID,
           let to = folders.firstIndex(where: { $0.id == targetID }) {
            folders.insert(folder, at: to)
        } else {
            folders.append(folder)
        }
    }

    private func persistFolders(_ folders: [Folder]) {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        defaults.set(data, forKey: Self.foldersKey)
    }

    func addFolder() {
        folders.append(Folder(id: UUID().uuidString, name: "Nova pasta"))
    }

    func removeFolder(_ id: String) {
        folders.removeAll { $0.id == id }
        membership = membership.filter { $0.value != id }
    }

    var active: ChatModel? {
        guard let selectedID else { return nil }
        return chats[selectedID]
    }

    func isLive(_ id: UUID) -> Bool {
        chats[id]?.isLive ?? false
    }

    enum SessionIndicator {
        case unread, working, waiting, rateLimited
    }

    func indicator(for id: UUID) -> SessionIndicator? {
        guard let chat = chats[id] else { return nil }
        if chat.isRateLimited { return .rateLimited }
        if chat.pending != nil || chat.pendingQuestion != nil { return .waiting }
        if chat.isBusy { return .working }
        if chat.hasUnread { return .unread }
        return nil
    }

    private func adopt(_ chat: ChatModel) {
        let id = chat.sessionID
        chat.isViewed = { [weak self] in
            self?.selectedID == id && NSApplication.shared.isActive
        }
        chat.metadataDidChange = { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }
    }

    private var filteredSummaries: [SessionSummary] {
        search.isEmpty ? summaries : summaries.filter {
            $0.title.localizedCaseInsensitiveContains(search)
            || $0.workingDirectory.lastPathComponent.localizedCaseInsensitiveContains(search)
        }
    }

    var folderGroups: [Group] {
        let byFolder = Dictionary(grouping: filteredSummaries) {
            membership[$0.id.uuidString] ?? ""
        }

        return folders.compactMap { folder -> Group? in
            let sessions = ordered(byFolder[folder.id] ?? [])

            if !search.isEmpty, sessions.isEmpty,
               !folder.name.localizedCaseInsensitiveContains(search) { return nil }
            return Group(folder: folder, sessions: sessions)
        }
    }

    var looseSessions: [SessionSummary] {
        let valid = Set(folders.map(\.id))
        return ordered(filteredSummaries.filter { summary in
            guard let folderID = membership[summary.id.uuidString] else { return true }
            return !valid.contains(folderID)
        })
    }

    struct Group: Identifiable {
        var folder: Folder
        var sessions: [SessionSummary]
        var id: String { folder.id }
        var name: String { folder.name }
    }

    // MARK: - Actions

    func refresh() async {
        guard let listing = try? await store.list() else { return }
        summaries = listing.sessions

        if !legacyPathToFolder.isEmpty {
            for summary in summaries where membership[summary.id.uuidString] == nil {
                if let folderID = legacyPathToFolder[summary.workingDirectory.path] {
                    membership[summary.id.uuidString] = folderID
                }
            }
            legacyPathToFolder = [:]
        }

        for broken in listing.unreadable {
            print("sessão ilegível em \(broken.location.path): \(broken.reason)")
        }
    }

    func newSession(assignedTo folderID: String? = nil,
                    harness: HarnessID? = nil) async {
        if let selectedID,
           let summary = summaries.first(where: { $0.id == selectedID }) {
            workingDirectory = summary.workingDirectory
        }
        let chat = ChatModel(store: store, workingDirectory: workingDirectory,
                             harness: harness ?? defaultHarness, cache: cache,
                             registry: registry, attachmentsRoot: attachmentsRoot)
        adopt(chat)
        await chat.persistMetadata()
        if let folderID { membership[chat.sessionID.uuidString] = folderID }
        chats[chat.sessionID] = chat
        selectedID = chat.sessionID
        await refresh()
        await chat.start()
    }

    func select(_ id: UUID) async {
        selectedID = id
        if let chat = chats[id] {
            if chat.hasUnread { chat.hasUnread = false }
            return
        }
        guard let session = try? await store.load(id) else { return }
        let chat = ChatModel(store: store, restoring: session, cache: cache,
                             registry: registry, attachmentsRoot: attachmentsRoot)
        adopt(chat)
        chats[id] = chat
    }

    func deleteSession(_ id: UUID) async {
        if let chat = chats[id] { await chat.stop() }
        chats[id] = nil
        membership[id.uuidString] = nil
        sessionOrder.removeAll { $0 == id.uuidString }
        if selectedID == id { selectedID = nil }
        try? await store.delete(id)
        await refresh()
    }

    func stopAll() async {
        for chat in chats.values { await chat.stop() }
    }
}
