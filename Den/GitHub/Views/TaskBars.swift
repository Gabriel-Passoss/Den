import SwiftUI

struct TaskBars: View {
    let chat: ChatModel

    @Environment(WorktreeModel.self) private var worktrees
    @Environment(PullRequestMonitor.self) private var monitor
    @AppStorage(GitHubCLI.pathKey) private var ghPath = ""

    var body: some View {
        let id = chat.sessionID
        let bars = monitor.bars(for: id)
        let setup = monitor.setupNeeded(for: id)
        if setup != nil || !bars.isEmpty {
            VStack(spacing: 6) {
                if let setup {
                    GitHubSetupBar(state: setup, choose: chooseGh,
                                   retry: { Task { await monitor.reconfigure(path: ghPath.isEmpty ? nil : ghPath) } },
                                   dismiss: { monitor.hideSetup(for: id) })
                }
                ForEach(bars) { bar in
                    PullRequestBar(repo: bar.repo,
                                   branch: worktrees.worktree(for: id)?.branch ?? "",
                                   pullRequest: bar.pullRequest,
                                   checkedAt: monitor.checkedAt(id, repo: bar.repo),
                                   refresh: { monitor.refresh(id, repo: bar.repo) },
                                   dismiss: {
                                       withAnimation(.easeOut(duration: 0.2)) {
                                           monitor.dismiss(id, repo: bar.repo)
                                       }
                                   })
                                   .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .aboveComposer(fade: 0.25)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: bars.map(\.id))
        }
    }

    private func chooseGh() {
        Task {
            if let chosen = await GhPathPicker.pick(for: monitor) { ghPath = chosen }
        }
    }
}
