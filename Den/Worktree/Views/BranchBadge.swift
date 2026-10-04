import SwiftUI
import AppKit

struct BranchBadge: View {
    let worktree: TaskWorktree
    var compact = false

    private var sections: [DenMenuSection] {
        [
            DenMenuSection(id: "repos", items: worktree.repos.map { repo in
                DenMenuItem(id: repo.id, title: "Mostrar \(repo.name) no Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([repo.worktree])
                }
            }),
            DenMenuSection(id: "branch", items: [
                DenMenuItem(id: "copy", title: "Copiar nome da branch") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(worktree.branch, forType: .string)
                },
            ]),
        ]
    }

    var body: some View {
        DenMenuChip(sections: sections) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 12))
                if !compact {
                    Text(worktree.branch)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 200)
                }
                Chevron(size: 8)
            }
            .foregroundStyle(Theme.accentSoft)
            .chipLabel()
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1))
        }
        .help(worktree.repos.map(\.worktree.path).joined(separator: "\n"))
        .accessibilityIdentifier("worktree-branch")
        .accessibilityLabel(worktree.branch)
    }
}
