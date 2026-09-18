import SwiftUI

struct ContentView: View {
    @State private var workspace = WorkspaceModel()
    
    @State private var columns = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView(workspace: workspace)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            if let cockpit = workspace.active {
                ChatView(cockpit: cockpit)
            } else {
                empty
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .task { await workspace.refresh() }
    }

    /// Sem pasta nenhuma, criar uma conversa precisa perguntar ONDE primeiro —
    /// senão ela nasceria na pasta pessoal do usuário sem ele ter pedido.
    private func startFirstConversation() {
        if let folder = workspace.folders.first {
            Task { await workspace.newSession(in: folder) }
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Adicionar"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        workspace.addFolder(url)
        Task { await workspace.newSession(in: url) }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("Nenhuma conversa aberta")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button("Nova conversa") { startFirstConversation() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("")
    }
}

#Preview {
    ContentView()
}
