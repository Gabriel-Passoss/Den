import SwiftUI

struct WorktreeChip: View {
    let chat: ChatModel
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
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 8))
                Text("Worktree")
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Criar uma worktree para esta tarefa ao enviar")
        .accessibilityLabel("Worktree")
    }

    private func enabled(_ draft: WorktreeModel.Draft) -> some View {
        let tint = worktrees.blocker(for: chat) == nil ? InlineCode.color : Color.red
        let name = worktrees.branchName(for: chat, message: chat.prompt)
        return HStack(spacing: 4) {
            Button { worktrees.setEnabled(false, for: chat) } label: {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 8))
            }
            .buttonStyle(.plain)
            .help("Não criar worktree")
            .accessibilityLabel("Desligar worktree")
            if editing {
                InlineRenameField(initial: name,
                                  commit: { typed in Task { await worktrees.rename(typed, for: chat) } },
                                  done: { editing = false })
                    .font(.system(size: 10, design: .monospaced))
                    .frame(width: 220)
            } else {
                Button { editing = true } label: {
                    HStack(spacing: 4) {
                        Text(name)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "pencil").font(.system(size: 7))
                    }
                }
                .buttonStyle(.plain)
                .help("Editar o nome da branch")
                .accessibilityLabel(name)
            }
            if case .multiple(_, let repos) = worktrees.layout(for: chat) {
                Button { picking = true } label: {
                    HStack(spacing: 2) {
                        Text("· \(draft.chosen.count) repos")
                        Image(systemName: "chevron.down").font(.system(size: 6, weight: .bold))
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $picking, arrowEdge: .bottom) {
                    RepoPicker(chat: chat, repos: repos)
                }
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(tint)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(tint.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 1))
        .frame(maxWidth: 360)
        .fixedSize(horizontal: false, vertical: true)
    }
}
