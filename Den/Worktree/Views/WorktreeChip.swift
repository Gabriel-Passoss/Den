import SwiftUI

struct WorktreeChip: View {
    let chat: ChatModel
    var nameWidth: CGFloat = 240
    @Environment(WorktreeModel.self) private var worktrees
    @State private var editing = false
    @State private var picking = false

    var body: some View {
        let draft = worktrees.draft(for: chat)
        Group {
            if draft.isEnabled {
                enabled(draft)
            } else {
                disabled
            }
        }
        .accessibilityIdentifier("worktree-chip")
    }

    private var disabled: some View {
        Button { worktrees.setEnabled(true, for: chat) } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 12))
                Text("Worktree")
            }
            .foregroundStyle(Theme.textTertiary)
            .chipLabel()
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.borderControl, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
        }
        .buttonStyle(.denGhost)
        .fixedSize()
        .help("Criar uma worktree para esta tarefa ao enviar")
        .accessibilityLabel("Worktree")
    }

    private func enabled(_ draft: WorktreeModel.Draft) -> some View {
        let tint = worktrees.blocker(for: chat) == nil ? Theme.accentSoft : Theme.removed
        let name = worktrees.branchName(for: chat, message: chat.prompt)
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return HStack(spacing: 6) {
            Button { worktrees.setEnabled(false, for: chat) } label: {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("Não criar worktree")
            .accessibilityLabel("Desligar worktree")
            if editing {
                InlineRenameField(initial: name,
                                  commit: { typed in Task { await worktrees.rename(typed, for: chat) } },
                                  done: { editing = false })
                    .font(.system(size: 11.5, design: .monospaced))
                    .frame(width: nameWidth)
            } else {
                Button { editing = true } label: {
                    HStack(spacing: 5) {
                        Text(name)
                            .font(.system(size: 11.5, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: nameWidth)
                        Image(systemName: "pencil").font(.system(size: 9))
                    }
                }
                .buttonStyle(.plain)
                .help("Editar o nome da branch")
                .accessibilityLabel(name)
            }
            if case .multiple(_, let repos) = worktrees.layout(for: chat) {
                Button { picking = true } label: {
                    HStack(spacing: 4) {
                        Text("· \(draft.chosen.count) repos")
                        Chevron(size: 8)
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $picking, arrowEdge: .bottom) {
                    RepoPicker(chat: chat, repos: repos)
                }
            }
        }
        .foregroundStyle(tint)
        .chipLabel()
        .background(tint == Theme.removed ? Theme.removedFill : Theme.accentFill, in: shape)
        .overlay(shape.strokeBorder(tint.opacity(0.45), lineWidth: 1))
        .fixedSize()
    }
}
