import SwiftUI
import HarnessCore

struct ContentView: View {
    @State private var workspace = WorkspaceModel.live()

    @State private var columns = NavigationSplitViewVisibility.all

    @State private var gitChanges = GitChangesModel()

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView(workspace: workspace)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
        }
        .frame(minWidth: 860, minHeight: 560)
        .onChange(of: columns) {
            if columns != .all { columns = .all }
        }
        .task { await workspace.refresh() }
    }

    @ViewBuilder
    private var detail: some View {
        if let chat = workspace.active {
            ChatView(chat: chat, gitChanges: gitChanges)
        } else if workspace.selectedID != nil {
            sessionLoading
        } else {
            empty
        }
    }

    private func startFirstConversation() {
        Task { await workspace.newSession() }
    }

    @State private var loadingSpinnerVisible = false

    private var sessionLoading: some View {
        ProgressView()
            .controlSize(.small)
            .opacity(loadingSpinnerVisible ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("")
            .task {
                loadingSpinnerVisible = false
                try? await Task.sleep(for: .milliseconds(400))
                loadingSpinnerVisible = true
            }
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
