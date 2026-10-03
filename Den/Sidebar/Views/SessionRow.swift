import SwiftUI
import HarnessCore

struct SessionRow: View {
    let summary: SessionSummary
    let indicator: WorkspaceModel.SessionIndicator?
    var task: TaskBadge? = nil
    var select: () -> Void
    var rename: (String) -> Void
    var unfile: (() -> Void)? = nil
    var delete: () -> Void = {}

    @State private var isEditing = false

    private static let trailingInset: CGFloat = 6

    var body: some View {
        HStack(spacing: 8) {
            if task != nil {
                TaskGlyph(tone: task?.tone, harness: summary.harnesses.last)
            } else {
                HarnessBadge(harness: summary.harnesses.last, size: 18)
            }

            VStack(alignment: .leading, spacing: 1) {
                if isEditing {
                    InlineRenameField(initial: summary.title, commit: rename) {
                        isEditing = false
                    }
                } else {
                    Text(summary.title).lineLimit(1).truncationMode(.tail)
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let indicator {
                Circle()
                    .fill(Self.color(for: indicator))
                    .frame(width: 6, height: 6)
                    .help(Self.label(for: indicator))
                    .accessibilityLabel(Self.label(for: indicator))
            }
        }
        .padding(.trailing, Self.trailingInset)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            guard !isEditing else { return }
            select()
        })
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            Task { @MainActor in isEditing = true }
        })
        .contextMenu {
            Button("Renomear") { isEditing = true }
            if let unfile {
                Button("Remover da pasta", action: unfile)
            }
            Divider()
            Button("Apagar sessão…", role: .destructive, action: delete)
        }
    }

    static func color(for indicator: WorkspaceModel.SessionIndicator) -> Color {
        switch indicator {
        case .unread: .green
        case .working: .yellow
        case .waiting: .purple
        case .rateLimited: .red
        }
    }

    static func label(for indicator: WorkspaceModel.SessionIndicator) -> String {
        switch indicator {
        case .unread: "Resposta nova"
        case .working: "Trabalhando"
        case .waiting: "Aguardando sua decisão"
        case .rateLimited: "Tokens esgotados"
        }
    }

    private var subtitle: String {
        let when = summary.updatedAt.formatted(.relative(presentation: .named))
        if let task { return "\(task.detail) · \(when)" }
        guard let current = summary.harnesses.last else { return when }
        return "\(HarnessBadge.name(for: current)) · \(when)"
    }
}
