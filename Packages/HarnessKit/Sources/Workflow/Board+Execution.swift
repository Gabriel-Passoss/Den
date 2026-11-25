import Foundation

public extension Board {
    mutating func startExecution(of id: TaskID) throws {
        let index = try taskIndex(id)
        guard stage(tasks[index].stage)?.agent != nil else { throw WorkflowError.stageHasNoAgent }
        guard tasks[index].execution != .running else { throw WorkflowError.executionAlreadyRunning }
        tasks[index].pendencies.removeAll { $0.waitsForTheNextTurn }
        tasks[index].execution = .running
    }

    mutating func endExecution(of id: TaskID) throws {
        let index = try runningTaskIndex(id)
        tasks[index].stopExecution(becoming: .finished)
    }

    @discardableResult
    mutating func openDecision(_ decision: Decision, on id: TaskID) throws -> PendencyID {
        let index = try runningTaskIndex(id)
        return tasks[index].open(.decision(decision))
    }

    mutating func answerDecision(_ pendency: PendencyID) throws {
        let (task, position) = try pendencyPosition(pendency)
        guard tasks[task].pendencies[position].isDecision else { throw WorkflowError.notADecision }
        tasks[task].pendencies.remove(at: position)
        tasks[task].agentMovesInARow = 0
    }

    @discardableResult
    mutating func reportProblem(_ problem: Problem, on id: TaskID) throws -> PendencyID {
        let index = try taskIndex(id)
        return tasks[index].open(.problem(problem))
    }

    mutating func resolve(_ pendency: PendencyID) throws {
        let (task, position) = try pendencyPosition(pendency)
        tasks[task].pendencies.remove(at: position)
        tasks[task].agentMovesInARow = 0
    }

    mutating func registerUserAction(on id: TaskID) throws {
        tasks[try taskIndex(id)].agentMovesInARow = 0
    }

    internal func runningTaskIndex(_ id: TaskID) throws -> Int {
        let index = try taskIndex(id)
        guard tasks[index].execution == .running else { throw WorkflowError.executionNotRunning }
        return index
    }

    private func pendencyPosition(_ id: PendencyID) throws -> (task: Int, position: Int) {
        for (task, candidate) in tasks.enumerated() {
            if let position = candidate.pendencies.firstIndex(where: { $0.id == id }) {
                return (task, position)
            }
        }
        throw WorkflowError.unknownPendency
    }
}

extension BoardTask {
    @discardableResult
    mutating func open(_ kind: Pendency.Kind) -> PendencyID {
        let pendency = Pendency(kind: kind)
        pendencies.append(pendency)
        return pendency.id
    }
}
