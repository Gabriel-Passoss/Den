@testable import Den
import DenStore
import Foundation
import Testing
import Workflow
import WorkflowTestSupport

@MainActor
@Test func withoutAProjectTheBoardSaysSo() {
    let model = BoardModel(repository: scratchRepositories().boards)

    model.load()

    #expect(model.content == .noProject)
}

@MainActor
@Test func aNewProjectShowsABoardWithNoStages() throws {
    let boards = scratchRepositories().boards
    _ = try boards.createProject(named: "Den", at: URL(fileURLWithPath: "/tmp/den"))
    let model = BoardModel(repository: boards)

    model.load()

    #expect(model.content == .board(name: "Den", display: BoardDisplay(columns: [], needsMeCount: 0)))
}

@MainActor
@Test func theBoardShowsTheSavedStagesAndTasks() throws {
    var flow = try Flow()
    let id = try flow.task(in: flow.doing)
    let model = try model(showing: flow.board)

    model.load()

    #expect(display(of: model)?.columns.map(\.name) == ["Backlog", "Em andamento", "Testes", "Pronto"])
    #expect(display(of: model)?.columns[1].cards.map(\.id) == [id.rawValue])
}

@MainActor
@Test func aBoardThatCannotBeReadFails() {
    let model = BoardModel(repository: UnreadableBoards())

    model.load()

    #expect(model.content == .failed)
}

@MainActor
@Test func theCounterWalksThroughTheTasksThatNeedMeAndStartsOverAtTheEnd() throws {
    var flow = try Flow()
    let (failing, _) = try flow.taskWaitingWithAProblem()
    let concluded = try flow.runningTask(in: flow.testing)
    try flow.board.conclude(concluded, with: .undecided)
    _ = try flow.task(in: flow.doing)
    let model = try model(showing: flow.board)
    model.load()

    #expect(model.selectNextNeedingMe() == CardPlace(column: flow.doing.rawValue, card: failing.rawValue))
    #expect(model.selectNextNeedingMe() == CardPlace(column: flow.testing.rawValue, card: concluded.rawValue))
    #expect(model.selectNextNeedingMe()?.card == failing.rawValue)
    #expect(model.selectedTaskID == failing.rawValue)
}

@MainActor
@Test func theCounterStartsFromTheFirstTaskWhenTheSelectedOneDoesNotNeedMe() throws {
    var flow = try Flow()
    let calm = try flow.task(in: flow.doing)
    let (failing, _) = try flow.taskWaitingWithAProblem()
    let model = try model(showing: flow.board)
    model.load()
    model.select(calm.rawValue)

    #expect(model.selectNextNeedingMe()?.card == failing.rawValue)
}

@MainActor
@Test func theCounterDoesNothingWhenNothingNeedsMe() throws {
    var flow = try Flow()
    _ = try flow.task(in: flow.doing)
    let model = try model(showing: flow.board)
    model.load()

    #expect(model.selectNextNeedingMe() == nil)
    #expect(model.selectedTaskID == nil)
}

@MainActor
@Test func selectingTheSelectedCardClearsTheSelection() throws {
    var flow = try Flow()
    let id = try flow.task(in: flow.doing)
    let model = try model(showing: flow.board)
    model.load()

    model.select(id.rawValue)
    model.select(id.rawValue)

    #expect(model.selectedTaskID == nil)
}

@MainActor
private func model(showing board: Board) throws -> BoardModel {
    let boards = scratchRepositories().boards
    let project = try boards.createProject(named: "Den", at: URL(fileURLWithPath: "/tmp/den"))
    try boards.save(board, of: project.id)
    return BoardModel(repository: boards)
}

@MainActor
private func display(of model: BoardModel) -> BoardDisplay? {
    guard case .board(_, let display) = model.content else { return nil }
    return display
}

private struct UnreadableBoards: BoardRepository {
    struct Failure: Error {}

    func createProject(named name: String, at root: URL) throws -> Project { throw Failure() }

    func projects() throws -> [Project] { throw Failure() }

    func board(of project: ProjectID) throws -> Board { throw Failure() }

    func save(_ board: Board, of project: ProjectID) throws { throw Failure() }
}
