import Foundation
import Testing
import Workflow

let implementer = AgentID("implementer")
let tester = AgentID("tester")
let monday = Date(timeIntervalSince1970: 1_000)
let tuesday = Date(timeIntervalSince1970: 2_000)
let wednesday = Date(timeIntervalSince1970: 3_000)

func passage(_ text: String = "fiz a primeira parte; falta testar o caso vazio") -> Passage? {
    Passage(text)
}

struct Flow {
    var board = Board()
    let backlog: StageID
    let doing: StageID
    let testing: StageID
    let done: StageID

    init() throws {
        backlog = try board.addStage(named: "Backlog")
        doing = try board.addStage(named: "Em andamento", agent: implementer)
        testing = try board.addStage(named: "Testes", agent: tester)
        done = try board.addStage(named: "Pronto", isFinal: true)
    }

    mutating func task(in stage: StageID? = nil, at date: Date = monday) throws -> TaskID {
        let id = try board.createTask(titled: "Exportar relatório", at: date)
        if let stage, stage != backlog { try board.moveTask(id, to: stage, at: date) }
        return id
    }

    mutating func runningTask(in stage: StageID) throws -> TaskID {
        let id = try task(in: stage)
        try board.startExecution(of: id)
        return id
    }

    func current(_ id: TaskID) throws -> BoardTask {
        try #require(board.task(id))
    }
}
