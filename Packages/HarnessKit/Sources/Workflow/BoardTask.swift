import Foundation

public enum Origin: Sendable, Equatable {
    case den
    case external(app: String, key: String)
}

public enum Execution: Sendable, Equatable {
    case idle
    case running
    case finished
}

public enum SubtaskProgress: Sendable, Equatable {
    case pending
    case inProgress
    case done
}

public struct Subtask: Sendable, Equatable, Identifiable {
    public let id: SubtaskID
    public let title: String
    public internal(set) var progress: SubtaskProgress
    public internal(set) var execution: Execution

    public init(id: SubtaskID = SubtaskID(), title: String,
                progress: SubtaskProgress = .pending, execution: Execution = .idle) {
        self.id = id
        self.title = title
        self.progress = progress
        self.execution = execution
    }
}

public struct BoardTask: Sendable, Equatable, Identifiable {
    public let id: TaskID
    public let title: String
    public let details: String
    public let origin: Origin
    public internal(set) var stage: StageID
    public internal(set) var enteredStageAt: Date
    public internal(set) var execution: Execution
    public internal(set) var subtasks: [Subtask]
    public internal(set) var pendencies: [Pendency]
    public internal(set) var history: [Movement]
    public internal(set) var agentMovesInARow: Int

    public init(id: TaskID = TaskID(), title: String, details: String = "", origin: Origin = .den,
                stage: StageID, enteredStageAt: Date, execution: Execution = .idle,
                subtasks: [Subtask] = [], pendencies: [Pendency] = [], history: [Movement] = [],
                agentMovesInARow: Int = 0) {
        self.id = id
        self.title = title
        self.details = details
        self.origin = origin
        self.stage = stage
        self.enteredStageAt = enteredStageAt
        self.execution = execution
        self.subtasks = subtasks
        self.pendencies = pendencies
        self.history = history
        self.agentMovesInARow = agentMovesInARow
    }

    public var needsMe: Bool {
        !pendencies.isEmpty
    }

    public var hasOpenSubtasks: Bool {
        subtasks.contains { $0.progress != .done }
    }
}
