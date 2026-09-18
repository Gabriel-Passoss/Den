import Foundation
import Observation
import HarnessCore
import ClaudeHarness

/// Todas as conversas, e qual delas está aberta.
///
/// A sidebar lê daqui. Cada conversa viva tem um `CockpitModel` próprio, que
/// sobrevive à troca de seleção — mudar de sessão não derruba o processo da
/// anterior, que é o ponto inteiro de um orquestrador de múltiplas sessões.
@MainActor
@Observable
final class WorkspaceModel {
    var summaries: [SessionSummary] = []
    var selectedID: UUID?
    var search: String = ""
    /// A pasta que uma conversa NOVA vai usar.
    var workingDirectory: URL = URL(fileURLWithPath: NSHomeDirectory())

    private let store: FileTranscriptStore
    private var cockpits: [UUID: CockpitModel] = [:]

    init() {
        let root = URL.applicationSupportDirectory.appending(path: "DevSpace/sessions")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.store = FileTranscriptStore(root: root)
    }

    var active: CockpitModel? {
        guard let selectedID else { return nil }
        return cockpits[selectedID]
    }

    /// As conversas agrupadas por pasta, como a sidebar desenha.
    var groups: [Group] {
        let filtered = search.isEmpty ? summaries : summaries.filter {
            $0.title.localizedCaseInsensitiveContains(search)
            || $0.workingDirectory.lastPathComponent.localizedCaseInsensitiveContains(search)
        }
        let byFolder = Dictionary(grouping: filtered) { $0.workingDirectory.lastPathComponent }
        return byFolder
            .map { Group(name: $0.key, sessions: $0.value.sorted { $0.updatedAt > $1.updatedAt }) }
            .sorted { ($0.sessions.first?.updatedAt ?? .distantPast)
                    > ($1.sessions.first?.updatedAt ?? .distantPast) }
    }

    struct Group: Identifiable {
        var name: String
        var sessions: [SessionSummary]
        var id: String { name }
    }

    // MARK: - Ações

    func refresh() async {
        guard let listing = try? await store.list() else { return }
        summaries = listing.sessions
        // Uma conversa que existe em disco e não abre não some da lista sem
        // aviso — é o que `SessionListing.unreadable` existe para impedir.
        for broken in listing.unreadable {
            print("sessão ilegível em \(broken.location.path): \(broken.reason)")
        }
    }

    func newSession() async {
        let cockpit = CockpitModel(store: store, workingDirectory: workingDirectory)
        await cockpit.persistMetadata()
        cockpits[cockpit.sessionID] = cockpit
        selectedID = cockpit.sessionID
        await refresh()
        await cockpit.start()
    }

    /// Abre uma conversa da lista. Se ela já estiver viva, só troca a seleção;
    /// senão, carrega o transcript do disco.
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
