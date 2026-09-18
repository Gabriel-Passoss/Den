import SwiftUI
import HarnessCore

/// A lista de conversas, agrupada por pasta.
struct SidebarView: View {
    @Bindable var workspace: WorkspaceModel
    /// Pastas recolhidas, por nome. Em memória de propósito: é estado de
    /// arrumação da janela, não da conversa — nada aqui merece ir para o disco.
    @State private var collapsed: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            searchField
            list
            Divider()
            footer
        }
        .frame(minWidth: 240)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            TextField("Buscar sessões", text: $workspace.search)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
        .padding(10)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2, pinnedViews: .sectionHeaders) {
                Text("Sessões")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)

                ForEach(workspace.groups) { group in
                    folderHeader(group)
                    if !collapsed.contains(group.id) {
                        ForEach(group.sessions) { summary in
                            sessionRow(summary)
                        }
                    }
                }
            }
            .padding(.bottom, 10)
            .animation(.easeInOut(duration: 0.18), value: collapsed)
        }
    }

    private func folderHeader(_ group: WorkspaceModel.Group) -> some View {
        let isCollapsed = collapsed.contains(group.id)
        return Button {
            if isCollapsed { collapsed.remove(group.id) } else { collapsed.insert(group.id) }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                Image(systemName: "folder.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text(group.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                Text("\(group.sessions.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 5)
            // A linha inteira é o alvo do clique, e não só o texto: um alvo do
            // tamanho da palavra obriga a mirar.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sessionRow(_ summary: SessionSummary) -> some View {
        let isSelected = workspace.selectedID == summary.id
        return Button {
            Task { await workspace.select(summary.id) }
        } label: {
            HStack(spacing: 7) {
                HarnessBadge(harness: summary.harnesses.first)

                VStack(alignment: .leading, spacing: 1) {
                    Text(summary.title)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Text(subtitle(for: summary))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : .clear,
                        in: RoundedRectangle(cornerRadius: 7))
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Button {
                chooseDirectory()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder.badge.gearshape").font(.system(size: 10))
                    Text(abbreviated(workspace.workingDirectory))
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)

            HStack(spacing: 5) {
                HarnessBadge(harness: workspace.defaultHarness, size: 12)
                Text("\(HarnessBadge.name(for: workspace.defaultHarness)) · login da assinatura")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
        }
        .padding(10)
    }

    /// Os harnesses que hospedaram a conversa, mais quando ela mudou.
    ///
    /// Plural de propósito: uma sessão do DevSpace atravessa harnesses, e
    /// depois da troca a linha precisa contar os dois — é a feature, não um
    /// detalhe de formatação.
    private func subtitle(for summary: SessionSummary) -> String {
        let names = summary.harnesses.map(HarnessBadge.name(for:))
        let unique = NSOrderedSet(array: names).compactMap { $0 as? String }
        let when = summary.updatedAt.formatted(.relative(presentation: .named))
        return unique.isEmpty ? when : "\(unique.joined(separator: " → ")) · \(when)"
    }

    private func abbreviated(_ url: URL) -> String {
        url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = workspace.workingDirectory
        if panel.runModal() == .OK, let url = panel.url {
            workspace.workingDirectory = url
        }
    }
}
