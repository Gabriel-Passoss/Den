import Testing
import Foundation
import DenStore
import SQLiteKit
import Workflow
import WorkflowTestSupport

private func reopened(damagedBy damage: String? = nil,
                      _ tasks: (Flow) throws -> [BoardTask]) throws -> (saved: Board, loaded: Board) {
    let scratch = try ScratchStore()
    defer { scratch.remove() }
    let boards = try scratch.open().repositories.boards
    let project = try boards.createProject(named: "Den", at: URL(filePath: "/tmp/den/repo"))
    let flow = try Flow()
    let board = try Board(stages: flow.board.stages, tasks: tasks(flow))
    try boards.save(board, of: project.id)
    if let damage { try scratch.raw().write { try $0.executeScript(damage) } }
    return (board, try scratch.open().repositories.boards.board(of: project.id))
}

private func damaged(_ task: (Flow) throws -> BoardTask, by sql: String) throws -> (saved: BoardTask, loaded: BoardTask) {
    let (saved, loaded) = try reopened(damagedBy: sql) { try [task($0)] }
    return (saved.tasks[0], try #require(loaded.tasks.first))
}

@Test func theHistoryOfMovesComesBackAfterReopeningTheStore() throws {
    let (saved, loaded) = try reopened { flow in
        [
            BoardTask(title: "Exportar relatório", stage: flow.testing, enteredStageAt: wednesday, history: [
                Movement(from: flow.backlog, to: flow.doing, author: .user, at: monday),
                Movement(from: flow.doing, to: flow.testing, author: .agent(implementer),
                         at: Date(timeIntervalSince1970: 2_000.25), passage: passage()),
            ]),
            BoardTask(title: "Corrigir login", stage: flow.doing, enteredStageAt: tuesday, history: [
                Movement(from: flow.testing, to: flow.doing, author: .user, at: tuesday,
                         passage: passage("o teste do vazio falha")),
                Movement(from: flow.doing, to: flow.done, author: .agent(tester), at: wednesday),
            ]),
        ]
    }

    #expect(loaded == saved)
}

@Test func everyKindOfPendencyComesBackAfterReopeningTheStore() throws {
    let (saved, loaded) = try reopened { flow in
        let kinds: [Pendency.Kind] = try [
            .decision(.permission),
            .decision(.question),
            .stageFinished,
            .returned(#require(passage("preciso saber o formato da data"))),
            .chainLimitReached(destination: flow.testing, passage: #require(passage())),
            .problem(.moveRefused(.unknownStage)),
            .problem(.moveRefused(.sameStage)),
            .problem(.moveRefused(.missingPassage)),
            .problem(.moveRefused(.openSubtasks)),
            .problem(.passageFailed),
            .problem(.subagentFailed(SubtaskID())),
            .problem(.executionFailed("sem rede")),
            .problem(.interrupted),
            .problem(.unreadable),
        ]
        return [BoardTask(title: "Exportar relatório", stage: flow.doing, enteredStageAt: monday,
                          execution: .finished, pendencies: kinds.map { Pendency(kind: $0) })]
    }

    #expect(loaded == saved)
    #expect(loaded.tasks.map(\.needsMe) == [true])
}

private let unreadable = Pendency.Kind.problem(.unreadable)

@Test func aMoveThatDoesNotDecodeIsDroppedAndTheRestOfTheTaskLoads() throws {
    let (saved, task) = try damaged({ flow in
        BoardTask(title: "Exportar relatório", stage: flow.testing, enteredStageAt: tuesday, history: [
            Movement(from: flow.backlog, to: flow.doing, author: .user, at: monday),
            Movement(from: flow.doing, to: flow.testing, author: .agent(implementer), at: tuesday, passage: passage()),
        ])
    }, by: "UPDATE tasks SET history = json_set(history, '$[0].from', 'não é uma etapa')")

    #expect(task.history == [saved.history[1]])
    #expect(task.title == "Exportar relatório")
    #expect(task.stage == saved.stage)
}

@Test func aPendencyThatDoesNotDecodeBecomesAnUnreadableProblem() throws {
    let (saved, task) = try damaged({ flow in
        BoardTask(title: "Exportar relatório", stage: flow.doing, enteredStageAt: monday, execution: .finished,
                  pendencies: [Pendency(kind: .decision(.question)), Pendency(kind: .stageFinished)])
    }, by: "UPDATE tasks SET pendencies = json_set(pendencies, '$[0].kind', 'desconhecida')")

    #expect(task.pendencies == [Pendency(id: saved.pendencies[0].id, kind: unreadable), saved.pendencies[1]])
    #expect(task.needsMe)
}

@Test func pendenciesThatAreNotJSONStillLeaveTheTaskNeedingMe() throws {
    let (_, task) = try damaged({ flow in
        BoardTask(title: "Exportar relatório", stage: flow.doing, enteredStageAt: monday, execution: .finished,
                  pendencies: [Pendency(kind: .stageFinished)])
    }, by: "UPDATE tasks SET pendencies = 'não é JSON'")

    #expect(task.pendencies.map(\.kind) == [unreadable])
    #expect(task.needsMe)
}
