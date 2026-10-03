import SwiftUI

struct FolderHeader: View {
    let name: String
    let count: Int
    let isOpen: Bool
    let isDropTarget: Bool
    var toggle: () -> Void
    var rename: (String) -> Void
    var newSession: () -> Void
    var remove: () -> Void

    @State private var isEditing = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .rotationEffect(.degrees(isOpen ? 90 : 0))
                .frame(width: 12)
            Image(systemName: isOpen ? "folder.fill" : "folder")
                .font(.system(size: 13))
                .foregroundStyle(isOpen ? Theme.accent : Theme.textTertiary)
                .frame(width: 16)
            if isEditing {
                InlineRenameField(initial: name, commit: rename) { isEditing = false }
                    .font(.system(size: 13, weight: .medium))
            } else {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityLabel(count == 1 ? "1 conversa" : "\(count) conversas")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(
            isDropTarget ? Theme.accent.opacity(0.16)
                         : hovering ? Theme.hover.opacity(0.7) : .clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isDropTarget)
        .animation(.easeInOut(duration: 0.2), value: isOpen)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .simultaneousGesture(TapGesture().onEnded {
            guard !isEditing else { return }
            toggle()
        })
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            Task { @MainActor in isEditing = true }
        })
        .contextMenu {
            Button("Renomear") { isEditing = true }
            Button("Nova sessão aqui", action: newSession)
            Divider()
            Button("Remover pasta", action: remove)
        }
    }
}
