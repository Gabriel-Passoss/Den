import SwiftUI
import HarnessCore

/// A lista de conversas, agrupada por pasta.
struct SidebarView: View {
    @Bindable var workspace: WorkspaceModel

    /// Pastas recolhidas, por caminho. Em memória de propósito: é arrumação da
    /// janela, não da conversa — nada aqui merece ir para o disco.
    @State private var collapsed: Set<String> = []

    /// O que está sendo renomeado agora, se algo estiver.
    @State private var editing: EditTarget?
    @State private var draft = ""
    @FocusState private var editorFocused: Bool

    private enum EditTarget: Hashable {
        case folder(String)
        case session(UUID)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            list
        }
        .frame(minWidth: 250)
    }

    // MARK: - Topo

    private var topBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("Buscar sessões", text: $workspace.search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))

            Menu {
                // Onde a conversa nasce é escolhido AQUI, no gesto que a cria,
                // e não num seletor de "pasta atual" escondido no rodapé: um
                // estado global que decide onde a próxima coisa acontece é o
                // tipo de coisa que o usuário esquece de conferir.
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
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Nova sessão ou nova pasta")
        }
        .padding(10)
    }

    // MARK: - Lista

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(workspace.groups) { group in
                    folderHeader(group)
                    if !collapsed.contains(group.id) {
                        ForEach(group.sessions) { summary in
                            sessionRow(summary)
                        }
                        if group.sessions.isEmpty {
                            Text("nenhuma conversa nesta pasta")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 33)
                                .padding(.vertical, 3)
                        }
                    }
                }
            }
            .padding(.bottom, 10)
            .animation(.easeInOut(duration: 0.18), value: collapsed)
        }
    }

    private func folderHeader(_ group: WorkspaceModel.Group) -> some View {
        let isCollapsed = collapsed.contains(group.id)
        return HStack(spacing: 7) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
            Image(systemName: "folder.fill")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            if editing == .folder(group.id) {
                editor(size: 14, weight: .semibold) {
                    workspace.renameFolder(group.id, to: draft)
                }
            } else {
                Text(group.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)
            Text("\(group.sessions.count)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 5)
        // A linha inteira é o alvo: um alvo do tamanho da palavra obriga a mirar.
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { beginEditing(.folder(group.id), with: group.name) }
        .onTapGesture {
            if isCollapsed { collapsed.remove(group.id) } else { collapsed.insert(group.id) }
        }
        .contextMenu {
            Button("Renomear") { beginEditing(.folder(group.id), with: group.name) }
            Button("Nova sessão aqui") {
                workspace.workingDirectory = group.url
                Task { await workspace.newSession() }
            }
            Divider()
            Button("Remover da lista") { workspace.removeFolder(group.url) }
        }
    }

    private func sessionRow(_ summary: SessionSummary) -> some View {
        let isSelected = workspace.selectedID == summary.id
        return HStack(spacing: 7) {
            HarnessBadge(harness: summary.harnesses.first)

            VStack(alignment: .leading, spacing: 1) {
                if editing == .session(summary.id) {
                    editor(size: 12, weight: .regular) {
                        Task { await workspace.renameSession(summary.id, to: draft) }
                    }
                } else {
                    Text(summary.title)
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
                Text(subtitle(for: summary))
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.75))
                                               : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor : .clear,
                    in: RoundedRectangle(cornerRadius: 7))
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { beginEditing(.session(summary.id), with: summary.title) }
        .onTapGesture { Task { await workspace.select(summary.id) } }
        .contextMenu {
            Button("Renomear") { beginEditing(.session(summary.id), with: summary.title) }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Edição em linha

    /// O campo que aparece no lugar do rótulo enquanto se renomeia.
    ///
    /// Confirma no Enter, cancela no Esc, e confirma também ao perder o foco —
    /// clicar fora é o gesto mais natural de "terminei", e tratá-lo como
    /// cancelamento jogaria fora o que a pessoa acabou de digitar.
    private func editor(size: CGFloat, weight: Font.Weight,
                        commit: @escaping () -> Void) -> some View {
        TextField("", text: $draft)
            .textFieldStyle(.plain)
            .font(.system(size: size, weight: weight))
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
        // Um quadro depois: o campo só existe depois que a view redesenha, e
        // focar antes disso não encontra nada para focar.
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

    private func abbreviated(_ url: URL) -> String {
        url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
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
