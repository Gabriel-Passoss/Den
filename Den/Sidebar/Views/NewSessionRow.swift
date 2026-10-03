import HarnessCore
import SwiftUI

struct NewSessionRow: View {
    let workspace: WorkspaceModel

    var body: some View {
        Button {
            Task { await workspace.newSession() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                Text("Nova sessão")
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.denGhost)
        .contextMenu {
            ForEach(workspace.availableHarnesses, id: \.rawValue) { harness in
                Button("Nova sessão com \(HarnessBadge.name(for: harness))") {
                    Task { await workspace.newSession(harness: harness) }
                }
            }
        }
        .help("Iniciar uma sessão nova")
    }
}

struct SidebarEmptyList: View {
    let search: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: search.isEmpty ? "bubble.left.and.bubble.right"
                                                      : "magnifyingglass")
                .font(.system(size: 20))
                .foregroundStyle(Theme.textFaint)
            Text(search.isEmpty ? "Nenhuma conversa"
                                          : "Nada encontrado para \"\(search)\"")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}
