import SwiftUI
import Workflow

struct TaskCard: View {
    let card: CardDisplay
    var isSelected = false
    var isDragging = false
    @State private var isExpanded: Bool

    init(card: CardDisplay, isSelected: Bool = false, isDragging: Bool = false, isExpanded: Bool = false) {
        self.card = card
        self.isSelected = isSelected
        self.isDragging = isDragging
        _isExpanded = State(initialValue: isExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space8) {
            if let key = card.key {
                Text(key)
                    .font(.system(size: Theme.font11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
            }
            Text(card.title)
                .font(.system(size: Theme.font13, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            StatusIndicator(status: card.status, isAnimated: card.isActive)
            if let subtasks = card.subtasks {
                SubtaskProgressBar(count: subtasks)
                expandToggle
            }
            if isExpanded {
                VStack(alignment: .leading, spacing: Theme.space6) {
                    ForEach(card.subtaskRows) { SubtaskRow(subtask: $0) }
                }
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

    private var expandToggle: some View {
        Button {
            withAnimation(.snappy) { isExpanded.toggle() }
        } label: {
            HStack(spacing: Theme.space4) {
                Text(isExpanded ? "Recolher sub-tasks" : "Mostrar sub-tasks")
                    .font(.system(size: Theme.font11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                Chevron(size: 8)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
        }
        .buttonStyle(.plain)
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

private func taskCardPreview(key: String? = nil, title: String = "Exportar relatório", status: TaskStatus = .stopped,
                             subtasks: [Subtask] = [], rows: [TaskStatus] = [], selected: Bool = false,
                             dragging: Bool = false, expanded: Bool = false) -> some View {
    let subtaskRows = zip(subtasks, rows).map {
        SubtaskDisplay(id: $0.id, title: $0.title, status: $1, isAnimated: status == .running && $1 == .running)
    }
    return TaskCard(card: CardDisplay(id: TaskID(), key: key, title: title, status: status,
                                      subtasks: SubtaskCount(subtasks), subtaskRows: subtaskRows),
                    isSelected: selected, isDragging: dragging, isExpanded: expanded)
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

#Preview("Sem sub-tasks") { taskCardPreview(key: "DEN-42", status: .concluded) }

#Preview("Selecionado") { taskCardPreview(key: "DEN-42", status: .needsMe, selected: true) }

#Preview("Arrastando") { taskCardPreview(key: "DEN-42", status: .running, dragging: true) }

#Preview("Recolhido com progresso") {
    taskCardPreview(key: "DEN-42", status: .running,
                    subtasks: [Subtask(title: "Tela", progress: .done), Subtask(title: "API", execution: .running),
                               Subtask(title: "Testes")],
                    rows: [.concluded, .running, .notStarted])
}

#Preview("Expandido com uma falha") {
    taskCardPreview(key: "DEN-42", status: .failed,
                    subtasks: [Subtask(title: "Tela", progress: .done), Subtask(title: "API"),
                               Subtask(title: "Testes")],
                    rows: [.concluded, .failed, .notStarted], expanded: true)
}

#Preview("Todas concluídas") {
    taskCardPreview(key: "DEN-42", status: .concluded,
                    subtasks: [Subtask(title: "Tela", progress: .done), Subtask(title: "API", progress: .done)],
                    rows: [.concluded, .concluded], expanded: true)
}
