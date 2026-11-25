import Workflow

nonisolated enum BoardPresentation {
    static func columns(for board: Board) -> [ColumnDisplay] {
        board.stages.map { stage in
            ColumnDisplay(id: stage.id,
                          name: stage.name,
                          isFinal: stage.isFinal,
                          cards: board.tasks(in: stage.id).map { card(for: $0, in: stage) })
        }
    }

    private static func card(for task: BoardTask, in stage: Stage) -> CardDisplay {
        CardDisplay(id: task.id, title: task.title, status: status(of: task, in: stage),
                    subtasks: SubtaskCount(task.subtasks))
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

nonisolated struct ColumnDisplay: Equatable, Identifiable {
    static let finalStageLabel = "Etapa final"

    let id: StageID
    let name: String
    let isFinal: Bool
    let cards: [CardDisplay]

    var taskCount: Int {
        cards.count
    }
}

nonisolated struct CardDisplay: Equatable, Identifiable {
    let id: TaskID
    var key = ""
    let title: String
    let status: TaskStatus
    let subtasks: SubtaskCount?

    var isActive: Bool {
        status == .running
    }
}

nonisolated struct SubtaskCount: Equatable {
    let done: Int
    let total: Int

    init?(_ subtasks: [Subtask]) {
        guard !subtasks.isEmpty else { return nil }
        done = subtasks.count { $0.progress == .done }
        total = subtasks.count
    }

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
