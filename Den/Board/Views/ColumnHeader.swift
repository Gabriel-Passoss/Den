import SwiftUI

// periphery:ignore
struct ColumnHeader: View {
    let name: String
    let taskCount: Int
    let isFinal: Bool

    var body: some View {
        HStack(spacing: Theme.space6) {
            Text(name)
                .font(.system(size: Theme.font13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
            if isFinal {
                Image(systemName: "flag.checkered")
                    .font(.system(size: Theme.font11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityLabel(ColumnDisplay.finalStageLabel)
                    .help(ColumnDisplay.finalStageLabel)
            }
            Spacer(minLength: Theme.space4)
            Text("\(taskCount)")
                .font(.system(size: Theme.font11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
                .accessibilityLabel(taskCount == 1 ? "1 task" : "\(taskCount) tasks")
        }
        .padding(.horizontal, Theme.space10)
        .padding(.vertical, Theme.space8)
    }
}

#Preview("Etapa comum") {
    ColumnHeader(name: "Em andamento", taskCount: 3, isFinal: false).frame(width: 280)
}

#Preview("Etapa final") {
    ColumnHeader(name: "Pronto", taskCount: 12, isFinal: true).frame(width: 280)
}

#Preview("Nome longo") {
    ColumnHeader(name: "Revisão de código com o time de plataforma e segurança", taskCount: 4, isFinal: true)
        .frame(width: 280)
}

#Preview("Contagem alta") {
    ColumnHeader(name: "Backlog", taskCount: 1_284, isFinal: false).frame(width: 280)
}
