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
        didSet { Self.persistFolders(folders) }
    }

    var membership: [String: String] = [:] {
        didSet { UserDefaults.standard.set(membership, forKey: Self.membershipKey) }
    }

    var sessionOrder: [String] = [] {
        didSet { UserDefaults.standard.set(sessionOrder, forKey: Self.orderKey) }
    }

    var defaultHarness: HarnessID {
        get { HarnessRegistry.preferred }
        set { HarnessRegistry.preferred = newValue }
    }

    var availableHarnesses: [HarnessID] { HarnessRegistry.all.map(\.id) }

    private let store: FileTranscriptStore
    private var cockpits: [UUID: CockpitModel] = [:]
    private var legacyPathToFolder: [String: String] = [:]

    private static let foldersKey = "DevSpace.folders.v2"
    private static let membershipKey = "DevSpace.sessionFolders"
    private static let orderKey = "DevSpace.sessionOrder"
    private static let legacyFoldersKey = "DevSpace.folders"
    private static let legacyNamesKey = "DevSpace.folderNames"

    init() {
        let root = URL.applicationSupportDirectory.appending(path: "DevSpace/sessions")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.store = FileTranscriptStore(root: root)

        let defaults = UserDefaults.standard
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
            Self.persistFolders(migrated)
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
        cockpits[id]?.adoptTitle(trimmed)
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

    private static func persistFolders(_ folders: [Folder]) {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        UserDefaults.standard.set(data, forKey: foldersKey)
    }

    func addFolder() {
        folders.append(Folder(id: UUID().uuidString, name: "Nova pasta"))
    }

    func removeFolder(_ id: String) {
        folders.removeAll { $0.id == id }
        membership = membership.filter { $0.value != id }
    }

    var active: CockpitModel? {
        guard let selectedID else { return nil }
        return cockpits[selectedID]
    }

    func isLive(_ id: UUID) -> Bool {
        cockpits[id]?.isLive ?? false
    }

    enum SessionIndicator {
        case unread, working, waiting, rateLimited
    }

    func indicator(for id: UUID) -> SessionIndicator? {
        guard let cockpit = cockpits[id] else { return nil }
        if cockpit.isRateLimited { return .rateLimited }
        if cockpit.pending != nil || cockpit.pendingQuestion != nil { return .waiting }
        if cockpit.isBusy { return .working }
        if cockpit.hasUnread { return .unread }
        return nil
    }

    private func adopt(_ cockpit: CockpitModel) {
        let id = cockpit.sessionID
        cockpit.isViewed = { [weak self] in
            self?.selectedID == id && NSApplication.shared.isActive
        }
        cockpit.metadataDidChange = { [weak self] in
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

    // MARK: - Ações

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
        let cockpit = CockpitModel(store: store, workingDirectory: workingDirectory,
                                   harness: harness ?? defaultHarness)
        adopt(cockpit)
        await cockpit.persistMetadata()
        if let folderID { membership[cockpit.sessionID.uuidString] = folderID }
        cockpits[cockpit.sessionID] = cockpit
        selectedID = cockpit.sessionID
        await refresh()
        await cockpit.start()
    }

    func select(_ id: UUID) async {
        selectedID = id
        if let cockpit = cockpits[id] {
            if cockpit.hasUnread { cockpit.hasUnread = false }
            return
        }
        guard let session = try? await store.load(id) else { return }
        let cockpit = CockpitModel(store: store, restoring: session)
        adopt(cockpit)
        cockpits[id] = cockpit
    }

    func deleteSession(_ id: UUID) async {
        if let cockpit = cockpits[id] { await cockpit.stop() }
        cockpits[id] = nil
        membership[id.uuidString] = nil
        sessionOrder.removeAll { $0 == id.uuidString }
        if selectedID == id { selectedID = nil }
        try? await store.delete(id)
        await refresh()
    }

    func stopAll() async {
        for cockpit in cockpits.values { await cockpit.stop() }
    }
}
