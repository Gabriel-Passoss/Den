import AppKit
import SwiftUI

struct TaskLifecycle: ViewModifier {
    let chat: ChatModel

    @Environment(WorktreeModel.self) private var worktrees
    @Environment(PullRequestMonitor.self) private var monitor

    func body(content: Content) -> some View {
        content
            .task(id: chat.sessionID) { await worktrees.reconcile(chat) }
            .task(id: chat.sessionID) {
                let id = chat.sessionID
                monitor.appear(id)
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3600))
                }
                monitor.disappear(id)
            }
            .onChange(of: chat.isBusy) {
                guard !chat.isBusy else { return }
                worktrees.clearWarning(chat.sessionID)
                Task { @MainActor in
                    await worktrees.reconcile(chat)
                    monitor.turnEnded(chat.sessionID)
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification)) { _ in
                Task { @MainActor in
                    await worktrees.reconcile(chat)
                    monitor.appBecameActive()
                }
            }
    }
}

extension View {
    func followsTask(of chat: ChatModel) -> some View {
        modifier(TaskLifecycle(chat: chat))
    }
}
