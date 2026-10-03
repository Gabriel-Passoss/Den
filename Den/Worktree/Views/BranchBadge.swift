import SwiftUI
import AppKit

struct BranchBadge: View {
    let worktree: TaskWorktree

    var body: some View {
        Menu {
            ForEach(worktree.repos) { repo in
                Button("Mostrar \(repo.name) no Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([repo.worktree])
                }
            }
            Divider()
            Button("Copiar nome da branch") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(worktree.branch, forType: .string)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 8))
                Text(worktree.folderName)
            }
            .font(.system(size: 10))
            .foregroundStyle(InlineCode.color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(InlineCode.color.opacity(0.14), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(worktree.repos.map(\.worktree.path).joined(separator: "\n"))
        .accessibilityIdentifier("worktree-branch")
        .accessibilityLabel(worktree.folderName)
    }
}
