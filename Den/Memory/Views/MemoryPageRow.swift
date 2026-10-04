import SwiftUI
import AppKit
import DenMemory

struct MemoryPageRow: View {
    let page: MemoryPage
    let file: URL
    let isOpen: Bool
    let toggle: () -> Void
    let delete: () -> Void

    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textFaint)
                        .frame(width: 10)
                        .accessibilityHidden(true)
                    Text(page.title)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                        .lineLimit(isOpen ? nil : 1)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Text(page.updated.formatted(.relative(presentation: .named)))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .hoverFill(selected: isOpen)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(page.title)
            .accessibilityAddTraits(isOpen ? [.isSelected] : [])

            if isOpen { detail }
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 10) {
            MarkdownText(text: page.body)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Button { NSWorkspace.shared.open(file) } label: {
                    Text("Abrir no editor").pillLabel()
                }
                .buttonStyle(.denSecondary)
                Button { NSWorkspace.shared.activateFileViewerSelecting([file]) } label: {
                    Text("Revelar no Finder").pillLabel()
                }
                .buttonStyle(.denGhost)
                Spacer()
                Button { confirmingDelete = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .iconLabel(size: 26)
                }
                .buttonStyle(.denGhost)
                .help("Apagar esta memória")
                .accessibilityLabel("Apagar memória")
            }
        }
        .padding(.leading, 26)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .confirmationDialog("Apagar \"\(page.title)\"?", isPresented: $confirmingDelete) {
            Button("Apagar", role: .destructive, action: delete)
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("O arquivo da memória é removido da wiki.")
        }
    }
}
