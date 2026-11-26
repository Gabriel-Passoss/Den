@testable import Den
import DenStore
import Foundation
import Testing
import Workflow
import WorkflowTestSupport

@MainActor
private final class MovingBoard {
    var date = monday
    var flow: Flow
    let boards: any BoardRepository
    let project: Project
    let model: BoardModel
    let id: TaskID

    init() throws {
        flow = try Flow()
        id = try flow.task(in: flow.doing)
        boards = scratchRepositories().boards
        project = try boards.createProject(named: "Den", at: URL(fileURLWithPath: "/tmp/den"))
        try boards.save(flow.board, of: project.id)
        var clock: MovingBoard?
        model = BoardModel(repository: boards, now: { clock?.date ?? monday }, wait: { _ in
            try await Task.sleep(for: .seconds(3600))
        })
        clock = self
        model.load()
    }

    func move(to stage: StageID, after seconds: TimeInterval = 0) {
        date = monday.addingTimeInterval(seconds)
        model.move(id.rawValue, to: stage.rawValue)
    }

    func settle(after seconds: TimeInterval) {
        date = monday.addingTimeInterval(seconds)
        model.settle()
    }

    func cards(in stage: StageID) -> [UUID] {
        guard case .board(_, let display) = model.content else { return [] }
        return display.columns.first { $0.id == stage.rawValue }?.cards.map(\.id) ?? []
    }

    func savedStage() throws -> StageID? {
        try boards.board(of: project.id).task(id)?.stage
    }
}

@MainActor
@Test func aMovedCardShowsInItsNewColumnWithDesfazerButIsNotSavedYet() throws {
    let board = try MovingBoard()

    board.move(to: board.flow.testing)

    #expect(board.cards(in: board.flow.testing) == [board.id.rawValue])
    #expect(board.cards(in: board.flow.doing).isEmpty)
    #expect(board.model.moveNotice == MoveNotice(task: "Exportar relatório", stage: "Testes"))
    #expect(try board.savedStage() == board.flow.doing)
}

@MainActor
@Test func desfazerWithinFiveSecondsPutsTheCardBackWhereItWas() throws {
    let board = try MovingBoard()
    board.move(to: board.flow.testing)

    #expect(board.model.moveNotice != nil)
    board.date = monday.addingTimeInterval(4.9)
    board.model.undo()

    #expect(board.cards(in: board.flow.doing) == [board.id.rawValue])
    #expect(board.model.moveNotice == nil)
    board.settle(after: 10)
    #expect(try board.savedStage() == board.flow.doing)
}

@MainActor
@Test func afterFiveSecondsTheMoveIsSavedAndCanNoLongerBeUndone() throws {
    let board = try MovingBoard()
    board.move(to: board.flow.testing)

    board.settle(after: 4.9)
    #expect(try board.savedStage() == board.flow.doing)
    #expect(board.model.moveNotice != nil)
    board.settle(after: 5)
    board.model.undo()

    #expect(try board.savedStage() == board.flow.testing)
    #expect(board.cards(in: board.flow.testing) == [board.id.rawValue])
    #expect(board.model.moveNotice == nil)
}

@MainActor
@Test func droppingACardOnItsOwnColumnChangesNothing() throws {
    let board = try MovingBoard()

    board.move(to: board.flow.doing)

    #expect(board.model.moveNotice == nil)
    #expect(board.cards(in: board.flow.doing) == [board.id.rawValue])
}

@MainActor
@Test func quittingWithAnOpenMoveSavesIt() throws {
    let board = try MovingBoard()
    board.move(to: board.flow.done)

    board.model.finishMove()

    #expect(try board.savedStage() == board.flow.done)
    #expect(board.model.moveNotice == nil)
}

@MainActor
@Test func theWindowClosesByItselfOnceTheWaitIsOver() async throws {
    let boards = scratchRepositories().boards
    var flow = try Flow()
    let id = try flow.task(in: flow.doing)
    let project = try boards.createProject(named: "Den", at: URL(fileURLWithPath: "/tmp/den"))
    try boards.save(flow.board, of: project.id)
    var date = monday
    let model = BoardModel(repository: boards, now: { date }, wait: { _ in })
    model.load()

    model.move(id.rawValue, to: flow.testing.rawValue)
    date = monday.addingTimeInterval(5)
    while model.moveNotice != nil { await Task.yield() }

    #expect(try boards.board(of: project.id).task(id)?.stage == flow.testing)
}
