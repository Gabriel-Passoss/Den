import HarnessCore
import SwiftUI

struct SidebarHeader: View {
    let workspace: WorkspaceModel
    var lightsInset: CGFloat
    var collapse: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 4)
            MenuChip {
                Button("Nova sessão") { Task { await workspace.newSession() } }
                Menu("Nova sessão com") {
                    ForEach(workspace.availableHarnesses, id: \.rawValue) { harness in
                        Button {
                            Task { await workspace.newSession(harness: harness) }
                        } label: {
                            Label {
                                Text(HarnessBadge.name(for: harness))
                            } icon: {
                                HarnessBadge.menuIcon(for: harness)
                            }
                        }
                    }
                }
                Button("Nova pasta") { workspace.addFolder() }
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textMuted)
                    .iconLabel()
            }
            .help("Nova sessão ou nova pasta")
            .accessibilityLabel("Nova")
            SidebarButton(title: "Recolher barra lateral", action: collapse)
        }
        .padding(.leading, lightsInset + 6)
        .padding(.trailing, 10)
        .frame(height: Theme.headerHeight)
        .windowDragArea()
    }
}

struct SidebarSearch: View {
    @Bindable var workspace: WorkspaceModel

    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            TextField("Buscar sessões…", text: $workspace.search)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onExitCommand {
                    workspace.search = ""
                    searchFocused = false
                }
            if !workspace.search.isEmpty {
                Button {
                    workspace.search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Limpar busca")
                .accessibilityLabel("Limpar busca")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(searchFocused ? Theme.accent.opacity(0.55) : .clear, lineWidth: 1))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .onKeyboardShortcut("f", modifiers: [.command, .shift]) { searchFocused = true }
    }
}
