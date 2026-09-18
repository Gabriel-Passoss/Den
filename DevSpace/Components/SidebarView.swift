import SwiftUI
import HarnessCore

struct SidebarView: View {
    @Bindable var workspace: WorkspaceModel

    @State private var collapsed: Set<String> = []

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

    // MARK: - Lista

    @ViewBuilder
    private var list: some View {
        List(selection: selectionBinding) {
            ForEach(workspace.groups) { group in
                Section(isExpanded: expansion(group.id)) {
                    ForEach(group.sessions) { summary in
                        SessionRow(
                            summary: summary,
                            indicator: workspace.indicator(for: summary.id),
                            select: { Task { await workspace.select(summary.id) } },
                            rename: { name in
                                Task { await workspace.renameSession(summary.id, to: name) }
                            }
                        )
                        .tag(summary.id)
                    }
                    if group.sessions.isEmpty {
                        Text("nenhuma conversa")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                } header: {
                    FolderHeader(
                        name: group.name,
                        count: group.sessions.count,
                        toggle: { toggleCollapse(group.id) },
                        rename: { workspace.renameFolder(group.id, to: $0) },
                        newSession: { Task { await workspace.newSession(in: group.url) } },
                        remove: { workspace.removeFolder(group.url) }
                    )
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

    private var caption: some View {
        Text("Sessões")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 4)
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

    private func toggleCollapse(_ id: String) {
        Task { @MainActor in
            if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
        }
    }

    // MARK: - Ações

    private var newSessionTitle: String {
        workspace.folderForNewSession == nil ? "Nova sessão…" : "Nova sessão"
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
