import SwiftUI

struct RepoPicker: View {
    let chat: ChatModel
    let repos: [RepoCandidate]
    @Environment(WorktreeModel.self) private var worktrees

    var body: some View {
        let chosen = worktrees.draft(for: chat).chosen
        VStack(alignment: .leading, spacing: 6) {
            Text("Repos da tarefa").font(.system(size: 12, weight: .semibold))
            ForEach(repos) { repo in
                Toggle(isOn: Binding(get: { chosen.contains(repo.id) },
                                     set: { _ in worktrees.toggle(repo: repo.id, for: chat) })) {
                    HStack {
                        Text(repo.name).font(.system(size: 12))
                        Spacer(minLength: 12)
                        Text(relative(repo))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            Divider()
            Text("Cada repo ganha a mesma branch, a partir da branch padrão dele.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tint(InlineCode.color)
        .padding(12)
        .frame(width: 300)
    }

    private func relative(_ repo: RepoCandidate) -> String {
        let base = chat.workingDirectory.standardizedFileURL.path + "/"
        let path = repo.toplevel.path
        return (path.hasPrefix(base) ? String(path.dropFirst(base.count)) : repo.toplevel.lastPathComponent) + "/"
    }
}
