import SwiftUI
import HarnessCore

struct SessionRow: View {
    let summary: SessionSummary
    let isLive: Bool
    var select: () -> Void
    var rename: (String) -> Void

    @State private var isEditing = false

    private static let trailingInset: CGFloat = 6

    var body: some View {
        HStack(spacing: 8) {
            HarnessBadge(harness: summary.harnesses.first, size: 18)

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

            if isLive {
                Circle()
                    .fill(.orange)
                    .frame(width: 6, height: 6)
                    .help("Em execução")
                    .accessibilityLabel("Em execução")
            }
        }
        .padding(.trailing, Self.trailingInset)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            guard !isEditing else { return }
            select()
        })
        .simultaneousGesture(TapGesture(count: 2).onEnded { isEditing = true })
        .contextMenu {
            Button("Renomear") { isEditing = true }
        }
    }

    private var subtitle: String {
        let names = summary.harnesses.map(HarnessBadge.name(for:))
        let unique = NSOrderedSet(array: names).compactMap { $0 as? String }
        let when = summary.updatedAt.formatted(.relative(presentation: .named))
        return unique.isEmpty ? when : "\(unique.joined(separator: " → ")) · \(when)"
    }
}
