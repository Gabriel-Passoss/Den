import Foundation

public struct Board: Sendable, Equatable {
    public internal(set) var stages: [Stage]
    public internal(set) var tasks: [BoardTask]

    public init(stages: [Stage] = [], tasks: [BoardTask] = []) {
        self.stages = stages
        self.tasks = tasks
    }

    @discardableResult
    public mutating func addStage(named name: String, agent: AgentID? = nil, isFinal: Bool = false) throws -> StageID {
        let stage = Stage(name: try Self.validName(name), agent: agent, isFinal: isFinal)
        stages.append(stage)
        return stage.id
    }

    public mutating func renameStage(_ id: StageID, to name: String) throws {
        let name = try Self.validName(name)
        stages[try stageIndex(id)].name = name
    }

    public mutating func moveStage(_ id: StageID, toPosition position: Int) throws {
        let stage = stages.remove(at: try stageIndex(id))
        stages.insert(stage, at: min(max(0, position), stages.count))
    }

    public mutating func assignAgent(_ agent: AgentID?, to id: StageID) throws {
        stages[try stageIndex(id)].agent = agent
    }

    public mutating func markFinal(_ isFinal: Bool, stage id: StageID) throws {
        stages[try stageIndex(id)].isFinal = isFinal
    }

    public mutating func removeStage(_ id: StageID) throws {
        let index = try stageIndex(id)
        guard !tasks.contains(where: { $0.stage == id }) else { throw WorkflowError.stageHasTasks }
        stages.remove(at: index)
    }

    public func stage(_ id: StageID) -> Stage? {
        stages.first { $0.id == id }
    }

    public func task(_ id: TaskID) -> BoardTask? {
        tasks.first { $0.id == id }
    }

    public func suggestedStage(after id: StageID) -> StageID? {
        guard let index = stages.firstIndex(where: { $0.id == id }), index + 1 < stages.count else { return nil }
        return stages[index + 1].id
    }

    public func tasks(in stage: StageID) -> [BoardTask] {
        tasks.filter { $0.stage == stage }.sorted { first, second in
            if first.needsMe != second.needsMe { return first.needsMe }
            return first.enteredStageAt < second.enteredStageAt
        }
    }

    public func isConcluded(_ id: TaskID) -> Bool {
        guard let task = task(id) else { return false }
        return stage(task.stage)?.isFinal ?? false
    }

    func stageIndex(_ id: StageID) throws -> Int {
        guard let index = stages.firstIndex(where: { $0.id == id }) else { throw WorkflowError.unknownStage }
        return index
    }

    func taskIndex(_ id: TaskID) throws -> Int {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { throw WorkflowError.unknownTask }
        return index
    }

    static func validName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WorkflowError.blankName }
        return trimmed
    }
}
