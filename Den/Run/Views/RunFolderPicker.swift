import SwiftUI

struct RunFolderPicker: View {
    let root: URL
    @Binding var selection: String

    @State private var folders: [RunFolder]?
    @State private var rootMarker: String?
    @State private var query = ""

    private var filtered: [RunFolder] {
        RunFolderIndex.filter(folders ?? [], query: query)
    }

    private var showsRoot: Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || root.lastPathComponent.localizedCaseInsensitiveContains(trimmed)
    }

    private var pinned: String? {
        guard let folders else { return nil }
        return RunFolderIndex.pinnedSelection(selection, in: folders)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                TextField("Buscar pasta", text: $query, prompt: Text("Buscar pasta"))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            Rectangle().fill(Theme.border).frame(height: 1)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let pinned {
                        row(path: pinned, title: pinned, marker: nil,
                            missing: !CommandSpec.directory(pinned, in: root).isExistingDirectory)
                    }
                    if showsRoot {
                        row(path: "", title: "Raiz do projeto (\(root.lastPathComponent))",
                            marker: rootMarker, missing: false)
                    }
                    ForEach(filtered) { folder in
                        row(path: folder.path, title: folder.path, marker: folder.marker, missing: false)
                    }
                    if folders == nil {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    } else if filtered.isEmpty, !showsRoot {
                        Text("Nenhuma pasta encontrada")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: 220)
        }
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(Theme.borderStrong, lineWidth: 1))
        .task(id: root.path) { await load() }
    }

    private func row(path: String, title: String, marker: String?, missing: Bool) -> some View {
        let isSelected = selection == path
        return Button {
            selection = path
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 12)
                Image(systemName: marker == nil ? "folder" : "diamond.fill")
                    .font(.system(size: marker == nil ? 11 : 8))
                    .foregroundStyle(marker == nil ? Theme.textTertiary : Theme.accent)
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 12.5, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if missing {
                    Text("Não existe")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.modified)
                } else if let marker {
                    Text(marker)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(isSelected ? Theme.hoverRaised : .clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func load() async {
        let root = root
        let (found, marker) = await Task.detached(priority: .userInitiated) {
            (RunFolderIndex.folders(under: root), RunFolderIndex.marker(in: root))
        }.value
        folders = found
        rootMarker = marker
    }
}
