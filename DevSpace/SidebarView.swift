import SwiftUI
import HarnessCore

/// A lista de conversas, agrupada por pasta.
struct SidebarView: View {
    @Bindable var workspace: WorkspaceModel

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
                    ForEach(group.sessions) { summary in
                        sessionRow(summary)
                    }
                }
            }
            .padding(.bottom, 10)
        }
    }

    private func folderHeader(_ group: WorkspaceModel.Group) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "folder")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(group.name)
                .font(.system(size: 11, weight: .medium))
            Spacer()
            Text("\(group.sessions.count)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 3)
    }

    private func sessionRow(_ summary: SessionSummary) -> some View {
        let isSelected = workspace.selectedID == summary.id
        return Button {
            Task { await workspace.select(summary.id) }
        } label: {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.orange)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Image(systemName: "sparkle")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(summary.title)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Text("Claude Code · \(summary.updatedAt.formatted(.relative(presentation: .named)))")
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
                Circle().fill(Color.orange).frame(width: 6, height: 6)
                Text("Claude Code · login da assinatura")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
        }
        .padding(10)
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
