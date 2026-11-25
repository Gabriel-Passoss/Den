import Foundation

public extension Board {
    @discardableResult
    mutating func createTask(titled title: String, details: String = "", origin: Origin = .den,
                             at date: Date = .now) throws -> TaskID {
        let title = try Self.validName(title)
        guard let first = stages.first else { throw WorkflowError.boardHasNoStages }
        let task = BoardTask(title: title, details: details, origin: origin, stage: first.id, enteredStageAt: date)
        tasks.append(task)
        return task.id
    }

    mutating func deleteTask(_ id: TaskID) throws {
        tasks.remove(at: try taskIndex(id))
    }

    mutating func moveTask(_ id: TaskID, to destination: StageID, at date: Date = .now) throws {
        let index = try taskIndex(id)
        _ = try stageIndex(destination)
        guard tasks[index].stage != destination else { throw WorkflowError.alreadyInStage }
        tasks[index].pendencies.removeAll { $0.waitsForTheNextTurn }
        tasks[index].agentMovesInARow = 0
        tasks[index].relocate(to: destination, by: .user, at: date, passage: nil)
    }

    func awaitsPassage(_ id: TaskID) -> Bool {
        guard let task = task(id), task.execution == .idle, let last = task.history.last,
              last.author == .user, last.passage == nil else { return false }
        return stage(last.from)?.agent != nil && stage(last.to)?.agent != nil
    }

    mutating func recordPassage(_ passage: Passage, for id: TaskID) throws {
        let index = try taskIndex(id)
        guard awaitsPassage(id) else { throw WorkflowError.noPassageAwaited }
        tasks[index].history[tasks[index].history.count - 1].passage = passage
    }
}

extension BoardTask {
    mutating func relocate(to destination: StageID, by author: Author, at date: Date, passage: Passage?) {
        history.append(Movement(from: stage, to: destination, author: author, at: date, passage: passage))
        stage = destination
        enteredStageAt = date
        stopSubagents(becoming: .idle)
        stopExecution(becoming: .idle)
    }

    mutating func interruptRunningExecutions() -> Bool {
        let wasRunning = execution == .running || subtasks.contains { $0.execution == .running }
        if execution == .running { execution = .idle }
        stopSubagents(becoming: .idle)
        return wasRunning
    }

    mutating func stopExecution(becoming state: Execution) {
        execution = state
        pendencies.removeAll { $0.isDecision }
        stopSubagents(becoming: .finished)
    }

    private mutating func stopSubagents(becoming state: Execution) {
        for index in subtasks.indices where subtasks[index].execution == .running {
            subtasks[index].execution = state
        }
    }
}
