import Foundation
import Observation
import HarnessCore
import ClaudeHarness

@MainActor
@Observable
final class WorkspaceModel {
    var summaries: [SessionSummary] = []
    var selectedID: UUID?
    var search: String = ""

    var workingDirectory: URL = URL(fileURLWithPath: NSHomeDirectory())

    var folders: [URL] = [] {
        didSet { Self.persist(folders) }
    }

    var folderNames: [String: String] = [:] {
        didSet { UserDefaults.standard.set(folderNames, forKey: Self.namesKey) }
    }

    let defaultHarness: HarnessID = .claudeCode

    private let store: FileTranscriptStore
    private var cockpits: [UUID: CockpitModel] = [:]

    private static let foldersKey = "DevSpace.folders"
    private static let namesKey = "DevSpace.folderNames"

    init() {
        let root = URL.applicationSupportDirectory.appending(path: "DevSpace/sessions")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.store = FileTranscriptStore(root: root)
        self.folders = (UserDefaults.standard.array(forKey: Self.foldersKey) as? [String] ?? [])
            .map { URL(fileURLWithPath: $0) }
        self.folderNames = UserDefaults.standard.dictionary(forKey: Self.namesKey) as? [String: String] ?? [:]
    }

    func renameFolder(_ path: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { folderNames[path] = nil } else { folderNames[path] = trimmed }
    }

    func renameSession(_ id: UUID, to title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var session = try? await store.load(id) else { return }
        session.title = trimmed
        try? await store.saveMetadata(session)
        cockpits[id]?.adoptTitle(trimmed)
        await refresh()
    }

    private static func persist(_ folders: [URL]) {
        UserDefaults.standard.set(folders.map(\.path), forKey: foldersKey)
    }

    func addFolder(_ url: URL) {
        if !folders.contains(where: { $0.path == url.path }) { folders.append(url) }
        workingDirectory = url
    }

    func removeFolder(_ url: URL) {
        folders.removeAll { $0.path == url.path }
    }

    var active: CockpitModel? {
        guard let selectedID else { return nil }
        return cockpits[selectedID]
    }

    func isLive(_ id: UUID) -> Bool {
        cockpits[id]?.isLive ?? false
    }

    var groups: [Group] {
        let matching = search.isEmpty ? summaries : summaries.filter {
            $0.title.localizedCaseInsensitiveContains(search)
            || $0.workingDirectory.lastPathComponent.localizedCaseInsensitiveContains(search)
        }
        let byPath = Dictionary(grouping: matching) { $0.workingDirectory.path }

        var paths = folders.map(\.path)
        for path in byPath.keys where !paths.contains(path) { paths.append(path) }

        return paths.compactMap { path -> Group? in
            let sessions = (byPath[path] ?? []).sorted { $0.updatedAt > $1.updatedAt }
            let url = URL(fileURLWithPath: path)

            if !search.isEmpty, sessions.isEmpty,
               !url.lastPathComponent.localizedCaseInsensitiveContains(search) { return nil }
            return Group(url: url, sessions: sessions,
                         name: folderNames[path] ?? url.lastPathComponent)
        }
        .sorted { ($0.sessions.first?.updatedAt ?? .distantPast)
                > ($1.sessions.first?.updatedAt ?? .distantPast) }
    }

    struct Group: Identifiable {
        var url: URL
        var sessions: [SessionSummary]
        var id: String { url.path }

        var name: String
    }

    // MARK: - Ações

    func refresh() async {
        guard let listing = try? await store.list() else { return }
        summaries = listing.sessions

        for broken in listing.unreadable {
            print("sessão ilegível em \(broken.location.path): \(broken.reason)")
        }
    }

    func displayName(for url: URL) -> String {
        folderNames[url.path] ?? url.lastPathComponent
    }

    var folderForNewSession: URL? {
        if let id = selectedID,
           let summary = summaries.first(where: { $0.id == id }) {
            return summary.workingDirectory
        }
        return folders.first
    }

    func newSession(in folder: URL) async {
        workingDirectory = folder
        await newSession()
    }

    func newSession() async {
        let cockpit = CockpitModel(store: store, workingDirectory: workingDirectory)
        await cockpit.persistMetadata()
        cockpits[cockpit.sessionID] = cockpit
        selectedID = cockpit.sessionID
        await refresh()
        await cockpit.start()
    }

    func select(_ id: UUID) async {
        selectedID = id
        guard cockpits[id] == nil else { return }
        guard let session = try? await store.load(id) else { return }
        cockpits[id] = CockpitModel(store: store, restoring: session)
    }

    func stopAll() async {
        for cockpit in cockpits.values { await cockpit.stop() }
    }
}
