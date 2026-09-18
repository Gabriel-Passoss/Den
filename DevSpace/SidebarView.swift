import SwiftUI
import HarnessCore

/// A lista de conversas, agrupada por pasta.
///
/// `List` com `.listStyle(.sidebar)` e não uma pilha desenhada à mão: a barra
/// lateral nativa traz a vibrância, o realce de seleção, o hover, a navegação
/// por teclado e os recuos corretos sem que nada disso precise ser imitado — e
/// imitação de controle nativo envelhece mal, porque o sistema muda e a
/// imitação não.
struct SidebarView: View {
    @Bindable var workspace: WorkspaceModel

    /// Pastas recolhidas, por caminho. Em memória de propósito: é arrumação da
    /// janela, não da conversa.
    @State private var collapsed: Set<String> = []

    @State private var editing: EditTarget?
    @State private var draft = ""
    @FocusState private var editorFocused: Bool

    private enum EditTarget: Hashable {
        case folder(String)
        case session(UUID)
    }

    var body: some View {
        List(selection: selectionBinding) {
            ForEach(workspace.groups) { group in
                Section(isExpanded: expansion(group.id)) {
                    ForEach(group.sessions) { summary in
                        sessionRow(summary).tag(summary.id)
                    }
                    if group.sessions.isEmpty {
                        Text("nenhuma conversa")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                } header: {
                    folderHeader(group)
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $workspace.search, placement: .sidebar, prompt: "Buscar sessões")
        .toolbar {
            ToolbarItem {
                Menu {
                    // Onde a conversa nasce é escolhido no gesto que a cria, e
                    // não num estado global de "pasta atual": um estado que
                    // decide onde a próxima coisa acontece é o tipo de coisa
                    // que se esquece de conferir antes de clicar.
                    if workspace.folders.isEmpty {
                        Button("Nova sessão…") { addFolderThenCreate() }
                    } else {
                        ForEach(workspace.folders, id: \.path) { folder in
                            Button("Nova sessão em \(workspace.displayName(for: folder))") {
                                Task { await workspace.newSession(in: folder) }
                            }
                        }
                    }
                    Divider()
                    Button("Adicionar pasta…") { addFolder() }
                } label: {
                    Label("Nova", systemImage: "plus")
                }
                .help("Nova sessão ou nova pasta")
            }
        }
    }

    // MARK: - Seleção

    /// A seleção da `List` e a do workspace são a mesma coisa, com um efeito
    /// colateral: escolher uma conversa fria a carrega do disco.
    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { workspace.selectedID },
            set: { id in
                guard let id else { return }
                Task { await workspace.select(id) }
            }
        )
    }

    private func expansion(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(id) },
            set: { open in if open { collapsed.remove(id) } else { collapsed.insert(id) } }
        )
    }

    // MARK: - Linhas

    private func folderHeader(_ group: WorkspaceModel.Group) -> some View {
        HStack(spacing: 6) {
            if editing == .folder(group.id) {
                editor { workspace.renameFolder(group.id, to: draft) }
            } else {
                Text(group.name).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Text("\(group.sessions.count)").foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { beginEditing(.folder(group.id), with: group.name) }
        .contextMenu {
            Button("Renomear") { beginEditing(.folder(group.id), with: group.name) }
            Button("Nova sessão aqui") {
                Task { await workspace.newSession(in: group.url) }
            }
            Divider()
            Button("Remover da lista") { workspace.removeFolder(group.url) }
        }
    }

    private func sessionRow(_ summary: SessionSummary) -> some View {
        HStack(spacing: 8) {
            HarnessBadge(harness: summary.harnesses.first, size: 16)

            VStack(alignment: .leading, spacing: 1) {
                if editing == .session(summary.id) {
                    editor { Task { await workspace.renameSession(summary.id, to: draft) } }
                } else {
                    Text(summary.title).lineLimit(1)
                }
                Text(subtitle(for: summary))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { beginEditing(.session(summary.id), with: summary.title) }
        .contextMenu {
            Button("Renomear") { beginEditing(.session(summary.id), with: summary.title) }
        }
    }

    // MARK: - Edição em linha

    /// O campo que aparece no lugar do rótulo enquanto se renomeia.
    ///
    /// Confirma no Enter, cancela no Esc, e confirma também ao perder o foco —
    /// clicar fora é o gesto mais natural de "terminei", e tratá-lo como
    /// cancelamento jogaria fora o que a pessoa acabou de digitar.
    private func editor(commit: @escaping () -> Void) -> some View {
        TextField("", text: $draft)
            .textFieldStyle(.plain)
            .focused($editorFocused)
            .onSubmit { commit(); editing = nil }
            .onExitCommand { editing = nil }
            .onChange(of: editorFocused) { _, focused in
                if !focused, editing != nil { commit(); editing = nil }
            }
    }

    private func beginEditing(_ target: EditTarget, with current: String) {
        draft = current
        editing = target
        // Um quadro depois: o campo só existe depois que a view redesenha.
        DispatchQueue.main.async { editorFocused = true }
    }

    // MARK: - Apoio

    /// Os harnesses que hospedaram a conversa, mais quando ela mudou.
    ///
    /// Plural de propósito: uma sessão do DevSpace atravessa harnesses, e
    /// depois da troca a linha precisa contar os dois — é a feature, não um
    /// detalhe de formatação.
    private func subtitle(for summary: SessionSummary) -> String {
        let names = summary.harnesses.map(HarnessBadge.name(for:))
        let unique = NSOrderedSet(array: names).compactMap { $0 as? String }
        let when = summary.updatedAt.formatted(.relative(presentation: .named))
        return unique.isEmpty ? when : "\(unique.joined(separator: " → ")) · \(when)"
    }

    @discardableResult
    private func addFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Adicionar"
        panel.directoryURL = workspace.workingDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        workspace.addFolder(url)
        return url
    }

    /// Primeira conversa do app: não há pasta nenhuma ainda, então escolher uma
    /// e criar a sessão é um gesto só.
    private func addFolderThenCreate() {
        guard let url = addFolder() else { return }
        Task { await workspace.newSession(in: url) }
    }
}
