import SwiftUI

struct SubtaskRow: View {
    let subtask: SubtaskDisplay

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.space8) {
            Text(subtask.title)
                .font(.system(size: Theme.font12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            StatusIndicator(status: subtask.status, isAnimated: subtask.isAnimated)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Estados") {
    VStack(alignment: .leading, spacing: Theme.space8) {
        ForEach([TaskStatus.failed, .running, .concluded, .notStarted], id: \.self) { status in
            SubtaskRow(subtask: SubtaskDisplay(id: UUID(), title: "Tela de exportação", status: status,
                                                  isAnimated: status == .running))
        }
    }
    .frame(width: 260)
    .padding(Theme.space24)
    .background(Theme.raised)
}
