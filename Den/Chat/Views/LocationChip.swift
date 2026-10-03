import AppKit
import SwiftUI

struct LocationChip: View {
    let chat: ChatModel
    var compact: Bool

    @Environment(WorktreeModel.self) private var worktrees

    var body: some View {
        if let worktree = worktrees.worktree(for: chat.sessionID) {
            BranchBadge(worktree: worktree, compact: compact)
        } else {
            folderChip.disabled(worktrees.isCreating(chat.sessionID))
        }
    }

    private var folderChip: some View {
        Button(action: chooseSessionFolder) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 12))
                if !compact {
                    Text(chat.workingDirectory.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 160)
                }
                Chevron(size: 8)
            }
            .foregroundStyle(Theme.textSecondary)
            .chipLabel()
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.borderStrong, lineWidth: 1))
        }
        .buttonStyle(.denGhost)
        .fixedSize()
        .help(chat.workingDirectory.path)
        .accessibilityLabel("Pasta da sessão: \(chat.workingDirectory.lastPathComponent)")
    }

    private func chooseSessionFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Usar"
        panel.directoryURL = chat.workingDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await chat.choose(directory: url) }
    }
}
