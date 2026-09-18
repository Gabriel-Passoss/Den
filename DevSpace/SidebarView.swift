import SwiftUI
import HarnessCore

struct SidebarView: View {
    @Bindable var workspace: WorkspaceModel

    @State private var collapsed: Set<String> = []

    @State private var editing: EditTarget?
    @State private var draft = ""
    @FocusState private var editorFocused: Bool

    private enum EditTarget: Hashable {
        case folder(String)
        case session(UUID)
    }

    private static let trailingInset: CGFloat = 6

    var body: some View {

        list
            .safeAreaInset(edge: .top, spacing: 0) { caption }

            .searchable(text: $workspace.search, placement: .sidebar, prompt: "Buscar sessões")

            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 460)
            .toolbar {

                ToolbarItem { Spacer() }
                ToolbarItem {
                    Menu {
                        Button(newSessionTitle, action: createSession)

                        Button("Novo grupo…") { addFolder() }
                    } label: {
                        Label("Nova", systemImage: "plus")
                    }
                    .help("Nova sessão ou novo grupo")
                }
            }
    }

    // MARK: - Ações

    private var caption: some View {
        Text("Sessões")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 4)
    }

    private var newSessionTitle: String {
        workspace.folderForNewSession == nil ? "Nova sessão…" : "Nova sessão"
    }

    // MARK: - Lista

    @ViewBuilder
    private var list: some View {
        List(selection: selectionBinding) {
            ForEach(workspace.groups) { group in
                Section(isExpanded: expansion(group.id)) {
                    ForEach(group.sessions) { summary in
                        sessionRow(summary).tag(summary.id)
                    }
                    if group.sessions.isEmpty {
                        Text("nenhuma conversa")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                } header: {
                    folderHeader(group)
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {

            if workspace.groups.isEmpty {
                if workspace.search.isEmpty {
                    ContentUnavailableView(
                        "Nenhuma conversa",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Crie um grupo a partir de uma pasta para começar.")
                    )
                } else {
                    ContentUnavailableView.search(text: workspace.search)
                }
            }
        }
    }

    // MARK: - Seleção

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

                Image(systemName: "folder")
                    .foregroundStyle(.tint)
                Text(group.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text("\(group.sessions.count)")
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel(group.sessions.count == 1
                                        ? "1 conversa" : "\(group.sessions.count) conversas")
            }
        }

        .padding(.trailing, Self.trailingInset)
        .contentShape(Rectangle())

        .simultaneousGesture(TapGesture().onEnded {
            guard editing != .folder(group.id) else { return }
            if collapsed.contains(group.id) { collapsed.remove(group.id) }
            else { collapsed.insert(group.id) }
        })
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            beginEditing(.folder(group.id), with: group.name)
        })
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
            HarnessBadge(harness: summary.harnesses.first, size: 18)

            VStack(alignment: .leading, spacing: 1) {
                if editing == .session(summary.id) {
                    editor { Task { await workspace.renameSession(summary.id, to: draft) } }
                } else {
                    Text(summary.title).lineLimit(1).truncationMode(.tail)
                }
                Text(subtitle(for: summary))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if workspace.isLive(summary.id) {

                Circle()
                    .fill(.orange)
                    .frame(width: 6, height: 6)
                    .help("Em execução")
                    .accessibilityLabel("Em execução")
            }
        }
        .padding(.trailing, Self.trailingInset)
        .padding(.vertical, 2)

        .contentShape(Rectangle())

        .simultaneousGesture(TapGesture().onEnded {
            Task { await workspace.select(summary.id) }
        })
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            beginEditing(.session(summary.id), with: summary.title)
        })
        .contextMenu {
            Button("Renomear") { beginEditing(.session(summary.id), with: summary.title) }
        }
    }

    // MARK: - Edição em linha

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

        DispatchQueue.main.async { editorFocused = true }
    }

    // MARK: - Apoio

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

    private func createSession() {
        if let folder = workspace.folderForNewSession {
            Task { await workspace.newSession(in: folder) }
        } else if let url = addFolder() {
            Task { await workspace.newSession(in: url) }
        }
    }
}
