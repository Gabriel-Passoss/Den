import Workflow

protocol StoredName: Equatable {
    static var everyCase: [Self] { get }
    var stored: String { get }
}

extension StoredName {
    init?(stored: String) {
        guard let match = Self.everyCase.first(where: { $0.stored == stored }) else { return nil }
        self = match
    }
}

extension Execution: StoredName {
    static let everyCase: [Execution] = [.idle, .running, .finished]

    var stored: String {
        switch self {
        case .idle: "idle"
        case .running: "running"
        case .finished: "finished"
        }
    }
}

extension SubtaskProgress: StoredName {
    static let everyCase: [SubtaskProgress] = [.pending, .inProgress, .done]

    var stored: String {
        switch self {
        case .pending: "pending"
        case .inProgress: "in_progress"
        case .done: "done"
        }
    }
}

extension Decision: StoredName {
    static let everyCase: [Decision] = [.permission, .question]

    var stored: String {
        switch self {
        case .permission: "permission"
        case .question: "question"
        }
    }
}

extension MoveRefusal: StoredName {
    static let everyCase: [MoveRefusal] = [.unknownStage, .sameStage, .missingPassage, .openSubtasks]

    var stored: String {
        switch self {
        case .unknownStage: "unknownStage"
        case .sameStage: "sameStage"
        case .missingPassage: "missingPassage"
        case .openSubtasks: "openSubtasks"
        }
    }
}
