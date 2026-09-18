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
        // Sem botão de nova conversa aqui: o "+" da sidebar já é esse gesto, e
        // duas portas para a mesma ação só fazem o usuário perguntar qual é a
        // certa.
        .task { await workspace.refresh() }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("Nenhuma conversa aberta")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button("Nova conversa") { Task { await workspace.newSession() } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Título vazio de propósito: sem conversa aberta não há o que a barra
        // de título possa dizer, e repetir o nome do app numa janela que já é
        // o app não informa nada.
        .navigationTitle("")
    }
}

#Preview {
    ContentView()
}
