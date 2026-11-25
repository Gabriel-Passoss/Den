import Foundation

extension Board {
    @discardableResult
    public mutating func conclude(_ id: TaskID, with conclusion: Conclusion,
                                  chainLimit: ChainLimit = .standard, at date: Date = .now) throws -> ConclusionOutcome {
        let index = try runningTaskIndex(id)
        guard let agent = stage(tasks[index].stage)?.agent else { throw WorkflowError.stageHasNoAgent }
        tasks[index].stopExecution(becoming: .finished)
        switch conclusion {
        case .undecided:
            tasks[index].open(.stageFinished)
            return .waitingForUser
        case .returnToUser(let passage):
            guard let passage else { return refuse(.missingPassage, task: index) }
            tasks[index].open(.returned(passage))
            return .waitingForUser
        case .move(let destination, let passage):
            if let refusal = refusal(of: tasks[index], to: destination, passage: passage) {
                return refuse(refusal, task: index)
            }
            guard let passage else { return refuse(.missingPassage, task: index) }
            guard tasks[index].agentMovesInARow < chainLimit.moves else {
                tasks[index].open(.chainLimitReached(destination: destination, passage: passage))
                return .chainLimitReached
            }
            tasks[index].relocate(to: destination, by: .agent(agent), at: date, passage: passage)
            tasks[index].agentMovesInARow += 1
            return .moved
        }
    }

    private func refusal(of task: BoardTask, to destination: StageID, passage: Passage?) -> MoveRefusal? {
        guard let target = stage(destination) else { return .unknownStage }
        if destination == task.stage { return .sameStage }
        if passage == nil { return .missingPassage }
        if target.isFinal, task.hasOpenSubtasks { return .openSubtasks }
        return nil
    }

    private mutating func refuse(_ refusal: MoveRefusal, task index: Int) -> ConclusionOutcome {
        tasks[index].open(.problem(.moveRefused(refusal)))
        return .refused(refusal)
    }
}
