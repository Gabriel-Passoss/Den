import SwiftUI

struct ContentView: View {
    @State private var workspace = WorkspaceModel()

    var body: some View {
        NavigationSplitView {
            SidebarView(workspace: workspace)
        } detail: {
            if let cockpit = workspace.active {
                ChatView(cockpit: cockpit)
            } else {
                empty
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await workspace.newSession() }
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .help("Nova conversa")
            }
        }
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
    }
}

#Preview {
    ContentView()
}
