import SwiftUI

struct RepoPicker: View {
    let chat: ChatModel
    let repos: [RepoCandidate]
    @Environment(WorktreeModel.self) private var worktrees

    var body: some View {
        let chosen = worktrees.draft(for: chat).chosen
        VStack(alignment: .leading, spacing: 12) {
            Text("Repos da tarefa")
                .font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                ForEach(repos) { repo in
                    RepoRow(name: repo.name, path: relative(repo), isChosen: chosen.contains(repo.id)) {
                        worktrees.toggle(repo: repo.id, for: chat)
                    }
                }
            }
            Text("Cada repo ganha a mesma branch, a partir da branch padrão dele.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 320)
        .foregroundStyle(Theme.text)
        .background(Theme.raised)
    }

    private func relative(_ repo: RepoCandidate) -> String {
        let base = chat.workingDirectory.standardizedFileURL.path + "/"
        let path = repo.toplevel.path
        return (path.hasPrefix(base) ? String(path.dropFirst(base.count)) : repo.toplevel.lastPathComponent) + "/"
    }
}

private struct RepoRow: View {
    let name: String
    let path: String
    let isChosen: Bool
    var toggle: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Image(systemName: isChosen ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundStyle(isChosen ? Theme.accent : Theme.textTertiary)
                Text(name)
                    .foregroundStyle(isChosen ? Theme.text : Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(path)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 6)
            .frame(height: 28)
            .hoverFill(hovering, radius: 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(name)
        .accessibilityValue(isChosen ? "marcado" : "desmarcado")
    }
}
