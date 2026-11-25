import Foundation
import Workflow

public let implementer = AgentID("implementer")
public let tester = AgentID("tester")
public let monday = Date(timeIntervalSince1970: 1_000)
public let tuesday = Date(timeIntervalSince1970: 2_000)
public let wednesday = Date(timeIntervalSince1970: 3_000)

public func passage(_ text: String = "fiz a primeira parte; falta testar o caso vazio") -> Passage? {
    Passage(text)
}

public struct Flow {
    public var board = Board()
    public let backlog: StageID
    public let doing: StageID
    public let testing: StageID
    public let done: StageID

    public init() throws {
        backlog = try board.addStage(named: "Backlog")
        doing = try board.addStage(named: "Em andamento", agent: implementer)
        testing = try board.addStage(named: "Testes", agent: tester)
        done = try board.addStage(named: "Pronto", isFinal: true)
    }

    public mutating func task(in stage: StageID? = nil, at date: Date = monday) throws -> TaskID {
        let id = try board.createTask(titled: "Exportar relatório", at: date)
        if let stage, stage != backlog { try board.moveTask(id, to: stage, at: date) }
        return id
    }

    public mutating func runningTask(in stage: StageID) throws -> TaskID {
        let id = try task(in: stage)
        try board.startExecution(of: id)
        return id
    }

    public mutating func runningTaskWithSubtask() throws -> (TaskID, SubtaskID) {
        let id = try runningTask(in: doing)
        return (id, try board.addSubtask(titled: "Tela", to: id))
    }

    public mutating func taskWaitingWithAProblem() throws -> (TaskID, PendencyID) {
        let id = try runningTask(in: doing)
        try board.conclude(id, with: .undecided)
        return (id, try board.reportProblem(.executionFailed("sem rede"), on: id))
    }
}
