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
    /// As pastas que o usuário adicionou.
    ///
    /// Persistidas, ao contrário do estado de recolhimento da sidebar: uma
    /// pasta vazia que o usuário acabou de adicionar não existe em lugar
    /// nenhum senão aqui — não há sessão de onde derivá-la —, então esquecê-la
    /// ao fechar o app apagaria trabalho do usuário, não arrumação de janela.
    var folders: [URL] = [] {
        didSet { Self.persist(folders) }
    }
    /// Apelidos das pastas, por caminho.
    ///
    /// O nome deixou de ser derivado do caminho porque o usuário pode
    /// renomeá-lo: duas pastas `src` em projetos diferentes são
    /// indistinguíveis na lista, e o caminho é quem manda de verdade — o
    /// apelido é só como ele prefere ler.
    var folderNames: [String: String] = [:] {
        didSet { UserDefaults.standard.set(folderNames, forKey: Self.namesKey) }
    }
    /// O harness que uma conversa nova sobe. Um dia isto vira escolha do
    /// usuário; hoje é o único que existe. Mora aqui e não na view porque
    /// saber QUAIS harnesses existem é trabalho do orquestrador.
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

    /// Renomeia uma pasta. Texto vazio devolve o nome do caminho.
    func renameFolder(_ path: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { folderNames[path] = nil } else { folderNames[path] = trimmed }
    }

    /// Renomeia uma conversa, no disco e na janela.
    ///
    /// Passa pelo store em vez de pelo `CockpitModel` aberto de propósito: o
    /// cockpit monta um `Session` de UM segmento só, e gravar metadados a
    /// partir dele apagaria os outros segmentos de uma conversa que já tivesse
    /// trocado de harness. Hoje isso não acontece — a troca não existe ainda —
    /// mas o caminho errado seria descoberto exatamente quando ela existir.
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

    /// Acrescenta uma pasta e passa a usá-la para conversas novas.
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

    /// As conversas agrupadas por pasta, como a sidebar desenha.
    ///
    /// Une duas origens: as pastas que o usuário adicionou (que aparecem mesmo
    /// vazias, senão adicioná-las não teria efeito visível) e as pastas que
    /// aparecem nas sessões em disco (que podem ser de antes de a lista
    /// existir, ou de uma sessão criada em outro lugar).
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
            // Numa busca, uma pasta sem resultado só fica se o nome dela casar.
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
        /// O apelido, quando há; senão o nome do caminho.
        var name: String
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

    /// Como a pasta se chama para quem lê: o apelido, quando há.
    func displayName(for url: URL) -> String {
        folderNames[url.path] ?? url.lastPathComponent
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
