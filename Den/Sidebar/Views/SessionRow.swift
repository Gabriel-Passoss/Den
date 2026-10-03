import SwiftUI
import HarnessCore

struct SessionRow: View {
    let summary: SessionSummary
    let indicator: WorkspaceModel.SessionIndicator?
    var task: TaskBadge? = nil
    var isSelected = false
    var select: () -> Void
    var rename: (String) -> Void
    var unfile: (() -> Void)? = nil
    var delete: () -> Void = {}

    @State private var isEditing = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            if task != nil {
                TaskGlyph(tone: task?.tone, harness: summary.harnesses.last)
            } else {
                HarnessBadge(harness: summary.harnesses.last, size: 18)
            }

            if isEditing {
                InlineRenameField(initial: summary.title, commit: rename) {
                    isEditing = false
                }
                .font(.system(size: 13))
            } else {
                Text(summary.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Theme.text : Theme.text.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityValue(task?.detail ?? "")
            }

            Spacer(minLength: 4)

            if let tag = task?.tag {
                Text(tag)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(task?.tone?.color ?? Theme.textTertiary)
                    .fixedSize()
            }

            if let indicator {
                Circle()
                    .fill(Self.color(for: indicator))
                    .frame(width: 6, height: 6)
                    .help(Self.label(for: indicator))
                    .accessibilityLabel(Self.label(for: indicator))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .hoverFill(hovering, selected: isSelected)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
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
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    static func color(for indicator: WorkspaceModel.SessionIndicator) -> Color {
        switch indicator {
        case .unread: Theme.added
        case .working: Theme.accent
        case .waiting: Theme.waiting
        case .rateLimited: Theme.removed
        }
    }

    static func label(for indicator: WorkspaceModel.SessionIndicator) -> String {
        switch indicator {
        case .unread: "Resposta nova"
        case .working: "Pensando"
        case .waiting: "Aguardando sua decisão"
        case .rateLimited: "Tokens esgotados"
        }
    }
}
