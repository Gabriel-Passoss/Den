import SwiftUI
import Workflow

struct TaskCard: View {
    let card: CardDisplay
    var isSelected = false
    var isDragging = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space8) {
            if !card.key.isEmpty {
                Text(card.key)
                    .font(.system(size: Theme.font11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
            }
            Text(card.title)
                .font(.system(size: Theme.font13, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            StatusIndicator(status: card.status)
            if let subtasks = card.subtasks {
                SubtaskProgressBar(count: subtasks)
            }
        }
        .padding(Theme.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: shape)
        .overlay(shape.strokeBorder(isSelected ? Theme.accent : Theme.borderCard,
                                    lineWidth: isSelected ? 1.5 : 1))
        .shadow(color: .black.opacity(isDragging ? 0.45 : 0), radius: isDragging ? 12 : 0, y: isDragging ? 6 : 0)
        .rotationEffect(.degrees(isDragging ? 1.5 : 0))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radius10, style: .continuous)
    }
}

private struct SubtaskProgressBar: View {
    let count: SubtaskCount

    var body: some View {
        HStack(spacing: Theme.space8) {
            ProgressView(value: Double(count.done), total: Double(count.total))
                .progressViewStyle(.linear)
                .tint(Theme.added)
            Text(count.label)
                .font(.system(size: Theme.font11, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.textMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sub-tasks concluídas: \(count.done) de \(count.total)")
    }
}

private func taskCardPreview(key: String = "", title: String = "Exportar relatório", status: TaskStatus = .stopped,
                             subtasks: [Subtask] = [], selected: Bool = false, dragging: Bool = false) -> some View {
    TaskCard(card: CardDisplay(id: TaskID(), key: key, title: title, status: status,
                               subtasks: SubtaskCount(subtasks)),
             isSelected: selected, isDragging: dragging)
        .frame(width: 260)
        .padding(Theme.space24)
        .background(Theme.sidebar)
}

#Preview("Com ID") { taskCardPreview(key: "DEN-42") }

#Preview("Sem ID") { taskCardPreview(status: .notStarted) }

#Preview("Título longo") {
    taskCardPreview(key: "DEN-7",
                    title: "Exportar o relatório mensal de vendas em PDF com filtros por região, período e vendedor")
}

#Preview("Com sub-tasks") {
    taskCardPreview(key: "DEN-42", status: .running,
                    subtasks: [Subtask(title: "Tela", progress: .done), Subtask(title: "API", progress: .inProgress),
                               Subtask(title: "Testes")])
}

#Preview("Sem sub-tasks") { taskCardPreview(key: "DEN-42", status: .concluded) }

#Preview("Selecionado") { taskCardPreview(key: "DEN-42", status: .needsMe, selected: true) }

#Preview("Arrastando") { taskCardPreview(key: "DEN-42", status: .running, dragging: true) }
