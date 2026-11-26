import Foundation

public struct UndoableMove: Sendable, Equatable {
    public static let window: TimeInterval = 5

    public let task: TaskID
    public let from: StageID
    public let to: StageID
    public let at: Date

    public init(task: TaskID, from: StageID, to: StageID, at: Date) {
        self.task = task
        self.from = from
        self.to = to
        self.at = at
    }

    public var expiresAt: Date {
        at.addingTimeInterval(Self.window)
    }

    public func isUndoable(at date: Date) -> Bool {
        date < expiresAt
    }
}

public struct UndoWindow: Sendable, Equatable {
    public private(set) var move: UndoableMove?

    public init() {}

    @discardableResult
    public mutating func open(_ id: TaskID, to destination: StageID, on board: Board,
                              at date: Date = .now) throws -> UndoableMove? {
        guard let task = board.task(id) else { throw WorkflowError.unknownTask }
        guard board.stage(destination) != nil else { throw WorkflowError.unknownStage }
        if let move, move.task == id, move.isUndoable(at: date) {
            guard move.to != destination else { throw WorkflowError.alreadyInStage }
            self.move = move.from == destination
                ? nil
                : UndoableMove(task: id, from: move.from, to: destination, at: date)
            return nil
        }
        let displaced = move
        let from = displaced?.task == id ? displaced?.to ?? task.stage : task.stage
        guard from != destination else { throw WorkflowError.alreadyInStage }
        move = UndoableMove(task: id, from: from, to: destination, at: date)
        return displaced
    }

    public mutating func undo(at date: Date = .now) throws -> UndoableMove {
        guard let move, move.isUndoable(at: date) else { throw WorkflowError.nothingToUndo }
        self.move = nil
        return move
    }

    public mutating func close(at date: Date = .now) -> UndoableMove? {
        guard let move, !move.isUndoable(at: date) else { return nil }
        self.move = nil
        return move
    }
}

public extension Board {
    mutating func complete(_ move: UndoableMove) throws {
        try moveTask(move.task, to: move.to, at: move.at)
    }

    func tasks(in stage: StageID, showing move: UndoableMove?) -> [BoardTask] {
        var shown = self
        if let move, let index = tasks.firstIndex(where: { $0.id == move.task }) {
            shown.tasks[index].stage = move.to
            shown.tasks[index].enteredStageAt = move.at
        }
        return shown.tasks(in: stage)
    }
}
