import SwiftUI

struct ComposerStatusChip: View {
    let chat: ChatModel
    let keys: ChatKeyMonitor

    @Environment(WorktreeModel.self) private var worktrees

    var body: some View {
        let waiting = chat.pending != nil || chat.pendingQuestion != nil
        let interrupting = chat.isBusy && keys.escArmed
        let note = worktrees.note(for: chat)
        if !waiting, interrupting || note != nil || (!chat.isBusy && visibleStatus != nil) {
            HStack(spacing: 7) {
                if interrupting {
                    Image(systemName: "escape")
                        .foregroundStyle(Theme.accentSoft)
                    Text("Esc de novo interrompe")
                } else if let note {
                    WorktreeNoteLabel(note: note)
                } else if let status = visibleStatus {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.modified)
                    Text(status)
                        .lineLimit(1)
                }
            }
            .transition(.opacity)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Theme.canvas.opacity(0.92), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.borderStrong, lineWidth: 1))
            .fixedSize()
            .offset(x: 10, y: -30)
            .allowsHitTesting(false)
        }
    }

    private var visibleStatus: String? {
        let status = chat.status
        guard status.hasPrefix("falhou") || status.hasPrefix("encerrada") else { return nil }
        return status.prefix(1).uppercased() + status.dropFirst()
    }
}
