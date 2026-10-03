import SwiftUI

struct WorktreeChip: View {
    let chat: ChatModel
    var compact = false
    @Environment(WorktreeModel.self) private var worktrees
    @State private var picking = false
    @State private var hovering = false
    @State private var hoveringRepos = false

    var body: some View {
        let draft = worktrees.draft(for: chat)
        HStack(spacing: 2) {
            Button { worktrees.setEnabled(!draft.isEnabled, for: chat) } label: {
                HStack(spacing: 7) {
                    Image(systemName: draft.isEnabled ? "checkmark.square.fill" : "square")
                        .font(.system(size: 14))
                        .foregroundStyle(draft.isEnabled ? Theme.accent : Theme.textTertiary)
                    if compact {
                        Image(systemName: "arrow.triangle.branch").font(.system(size: 12))
                    } else {
                        Text("Worktree")
                    }
                }
                .foregroundStyle(draft.isEnabled ? Theme.text : Theme.textSecondary)
                .chipLabel(horizontalPadding: 8)
                .hoverFill(hovering)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("Criar uma worktree para esta tarefa ao enviar; o Den escolhe o nome da branch")
            .accessibilityIdentifier("worktree-chip")
            .accessibilityLabel("Worktree")
            .accessibilityValue(draft.isEnabled ? "ligado" : "desligado")
            .accessibilityAddTraits(draft.isEnabled ? [.isSelected] : [])

            if draft.isEnabled, case .multiple(_, let repos) = worktrees.layout(for: chat) {
                Button { picking.toggle() } label: {
                    HStack(spacing: 5) {
                        Text(draft.chosen.count == 1 ? "1 repo" : "\(draft.chosen.count) repos")
                            .monospacedDigit()
                        Chevron(size: 8)
                    }
                    .foregroundStyle(draft.chosen.isEmpty ? Theme.removed : Theme.textSecondary)
                    .chipLabel(horizontalPadding: 8)
                    .hoverFill(hoveringRepos, selected: picking)
                }
                .buttonStyle(.plain)
                .onHover { hoveringRepos = $0 }
                .help("Escolher os repos da tarefa")
                .accessibilityLabel("Repos da tarefa")
                .popover(isPresented: $picking, arrowEdge: .top) {
                    RepoPicker(chat: chat, repos: repos)
                        .presentationBackground(Theme.raised)
                        .environment(\.colorScheme, .dark)
                }
            }
        }
        .fixedSize()
    }
}
