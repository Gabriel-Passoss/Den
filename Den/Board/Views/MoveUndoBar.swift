import SwiftUI

struct MoveUndoBar: View {
    let notice: MoveNotice
    let undo: () -> Void

    var body: some View {
        HStack(spacing: Theme.space12) {
            Text(notice.message)
                .font(.system(size: Theme.font13))
                .foregroundStyle(Theme.canvas)
                .lineLimit(1)
                .truncationMode(.middle)
            Button("Desfazer", action: undo)
                .buttonStyle(.plain)
                .font(.system(size: Theme.font13, weight: .semibold))
                .foregroundStyle(Theme.action)
                .keyboardShortcut("z", modifiers: .command)
        }
        .padding(.horizontal, Theme.space16)
        .padding(.vertical, Theme.space10)
        .background(Theme.onAction, in: Capsule())
        .shadow(color: Theme.liftShadow, radius: 12, y: 4)
        .frame(maxWidth: 520)
        .accessibilityElement(children: .contain)
        .onAppear { AccessibilityNotification.Announcement("\(notice.message). Desfazer disponível").post() }
        .onChange(of: notice) { _, notice in
            AccessibilityNotification.Announcement("\(notice.message). Desfazer disponível").post()
        }
    }
}

#Preview {
    MoveUndoBar(notice: MoveNotice(task: "Exportar relatório em CSV", stage: "Em andamento")) {}
        .padding()
        .background(Theme.canvas)
}
