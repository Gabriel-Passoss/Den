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

    private static let trailingInset: CGFloat = 6

    var body: some View {
        HStack(spacing: 6) {
            if isEditing {
                InlineRenameField(initial: name, commit: rename) { isEditing = false }
            } else {
                Image(systemName: isOpen ? "folder.fill" : "folder")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.tint)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.easeInOut(duration: 0.2), value: isOpen)
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text("\(count)")
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel(count == 1 ? "1 conversa" : "\(count) conversas")
            }
        }
        .padding(.trailing, Self.trailingInset)
        .padding(.vertical, 3)
        .background(
            isDropTarget ? AnyShapeStyle(Color.accentColor.opacity(0.18))
                         : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 6))
        .animation(.easeOut(duration: 0.12), value: isDropTarget)
        .contentShape(Rectangle())
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
