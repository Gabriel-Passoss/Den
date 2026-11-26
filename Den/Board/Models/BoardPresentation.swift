import Foundation
import Workflow

nonisolated enum BoardPresentation {
    static func display(of board: Board, showing move: UndoableMove? = nil) -> BoardDisplay {
        BoardDisplay(columns: board.stages.map { column(for: $0, on: board, showing: move) },
                     needsMeCount: board.tasks.count(where: \.needsMe))
    }

    private static func column(for stage: Stage, on board: Board, showing move: UndoableMove?) -> ColumnDisplay {
        ColumnDisplay(id: stage.id.rawValue,
                      name: stage.name,
                      isFinal: stage.isFinal,
                      cards: board.tasks(in: stage.id, showing: move).map { card(for: $0, in: stage) })
    }

    private static func card(for task: BoardTask, in stage: Stage) -> CardDisplay {
        let status = status(of: task, in: stage)
        return CardDisplay(id: task.id.rawValue, key: nil, title: task.title, status: status,
                           subtasks: progress(of: task.subtasks),
                           subtaskRows: task.subtasks.map { row(for: $0, of: task, onActiveCard: status == .running) })
    }

    private static func row(for subtask: Subtask, of task: BoardTask, onActiveCard: Bool) -> SubtaskDisplay {
        let status = status(of: subtask, in: task)
        return SubtaskDisplay(id: subtask.id.rawValue, title: subtask.title, status: status,
                              isAnimated: onActiveCard && status == .running)
    }

    private static func progress(of subtasks: [Subtask]) -> SubtaskCount? {
        guard !subtasks.isEmpty else { return nil }
        return SubtaskCount(done: subtasks.count { $0.progress == .done }, total: subtasks.count)
    }

    private static func status(of subtask: Subtask, in task: BoardTask) -> TaskStatus {
        if task.pendencies.contains(where: { $0.kind == .problem(.subagentFailed(subtask.id)) }) { return .failed }
        if subtask.progress == .done { return .concluded }
        return subtask.execution == .running ? .running : .notStarted
    }

    private static func status(of task: BoardTask, in stage: Stage) -> TaskStatus {
        if task.pendencies.contains(where: isProblem) { return .failed }
        if task.needsMe { return .needsMe }
        if isExecuting(task) { return .running }
        if stage.isFinal { return .concluded }
        return task.execution == .finished ? .stopped : .notStarted
    }

    private static func isExecuting(_ task: BoardTask) -> Bool {
        task.execution == .running || task.subtasks.contains { $0.execution == .running }
    }

    private static func isProblem(_ pendency: Pendency) -> Bool {
        if case .problem = pendency.kind { return true }
        return false
    }
}

nonisolated struct BoardDisplay: Equatable {
    let columns: [ColumnDisplay]
    let needsMeCount: Int
}

nonisolated struct ColumnDisplay: Equatable, Identifiable {
    static let finalStageLabel = "Etapa final"

    let id: UUID
    let name: String
    let isFinal: Bool
    let cards: [CardDisplay]

    var taskCount: Int {
        cards.count
    }
}

nonisolated struct CardDisplay: Equatable, Identifiable {
    let id: UUID
    let key: String?
    let title: String
    let status: TaskStatus
    let subtasks: SubtaskCount?
    var subtaskRows: [SubtaskDisplay] = []

    var isActive: Bool {
        status == .running
    }
}

nonisolated struct SubtaskDisplay: Equatable, Identifiable {
    let id: UUID
    let title: String
    let status: TaskStatus
    let isAnimated: Bool
}

nonisolated struct SubtaskCount: Equatable {
    let done: Int
    let total: Int

    var label: String {
        "\(done)/\(total)"
    }
}

nonisolated enum TaskStatus: Equatable, Sendable {
    case failed
    case needsMe
    case running
    case concluded
    case stopped
    case notStarted

    var label: String {
        switch self {
        case .failed: "Falhou"
        case .needsMe: "Precisa de você"
        case .running: "Em execução"
        case .concluded: "Concluído"
        case .stopped: "Parada"
        case .notStarted: "Não iniciada"
        }
    }
}
