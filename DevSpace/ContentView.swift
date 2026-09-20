import SwiftUI
import HarnessCore

struct ContentView: View {
    @State private var workspace = WorkspaceModel()

    @State private var columns = NavigationSplitViewVisibility.all

    @State private var gitChanges = GitChangesModel()

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {

            SidebarView(workspace: workspace)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            if let cockpit = workspace.active {
                ChatView(cockpit: cockpit, gitChanges: gitChanges)
            } else {
                empty
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .task {
            await workspace.refresh()
            #if DEBUG
            if ProcessInfo.processInfo.environment["DEVSPACE_FAKE"] != nil,
               let first = workspace.summaries.first {
                await workspace.select(first.id)
                let delayed = ProcessInfo.processInfo
                    .environment["DEVSPACE_FAKE_DELAY"].flatMap(Double.init)
                if let delayed {
                    try? await Task.sleep(for: .seconds(delayed))
                }
                let env = ProcessInfo.processInfo.environment
                if env["DEVSPACE_FAKE_UNREAD"] != nil {
                    workspace.active?.hasUnread = true
                }
                if env["DEVSPACE_FAKE_QUESTION"] != nil {
                workspace.active?.pendingQuestion = CockpitModel.QuestionPrompt(
                    id: "fake",
                    questions: [.init(
                        text: "Qual você prefere?",
                        header: "Escolha",
                        multiSelect: false,
                        options: [
                            .init(label: "Gato", detail: "Independente, dorme bastante"),
                            .init(label: "Cachorro", detail: "Leal, gosta de passear"),
                        ])],
                    request: PermissionRequest(id: "fake", toolName: "AskUserQuestion")
                )
                }
                if ProcessInfo.processInfo.environment["DEVSPACE_FAKE_BUSY"] != nil {
                    workspace.active?.isBusy = true
                    workspace.active?.turnStartedAt = Date()
                }
                if let interval = env["DEVSPACE_FAKE_SWITCH"].flatMap(Double.init) {
                    let workspace = self.workspace
                    Task { @MainActor in
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(interval))
                            let ids = workspace.summaries.map(\.id)
                            guard ids.count > 1, let current = workspace.selectedID,
                                  let index = ids.firstIndex(of: current) else { continue }
                            await workspace.select(ids[(index + 1) % ids.count])
                        }
                    }
                }
            }
            DebugSnapshot.arm()
            #endif
        }
    }

    private func startFirstConversation() {
        Task { await workspace.newSession() }
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
