import SwiftUI

struct FolderHeader: View {
    let name: String
    let count: Int
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
                Image(systemName: "folder")
                    .foregroundStyle(.tint)
                Text(name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text("\(count)")
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel(count == 1 ? "1 conversa" : "\(count) conversas")
            }
        }
        .padding(.trailing, Self.trailingInset)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            guard !isEditing else { return }
            toggle()
        })
        .simultaneousGesture(TapGesture(count: 2).onEnded { isEditing = true })
        .contextMenu {
            Button("Renomear") { isEditing = true }
            Button("Nova sessão aqui", action: newSession)
            Divider()
            Button("Remover da lista", action: remove)
        }
    }
}
