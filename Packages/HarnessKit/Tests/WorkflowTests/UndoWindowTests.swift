import Foundation
import Testing
import Workflow
import WorkflowTestSupport

private func seconds(_ value: TimeInterval) -> Date {
    monday.addingTimeInterval(value)
}

private struct OpenMove {
    var flow: Flow
    var window = UndoWindow()
    let id: TaskID

    init(running: Bool = false, to destination: KeyPath<Flow, StageID>) throws {
        flow = try Flow()
        id = running ? try flow.runningTask(in: flow.doing) : try flow.task()
        try window.open(id, to: flow[keyPath: destination], on: flow.board, at: monday)
    }

    mutating func moveAgain(to destination: KeyPath<Flow, StageID>, at date: Date) throws -> UndoableMove? {
        try window.open(id, to: flow[keyPath: destination], on: flow.board, at: date)
    }

    func shown(in stage: KeyPath<Flow, StageID>) -> [TaskID] {
        flow.board.tasks(in: flow[keyPath: stage], showing: window.move).map(\.id)
    }
}

@Test func undoingWithinFiveSecondsLeavesTheTaskInItsOriginStage() throws {
    var open = try OpenMove(running: true, to: \.testing)
    let before = open.flow.board

    let undone = try open.window.undo(at: seconds(4.9))

    #expect(undone == UndoableMove(task: open.id, from: open.flow.doing, to: open.flow.testing, at: monday))
    #expect(open.window.move == nil)
    #expect(open.flow.board == before)
    #expect(open.shown(in: \.doing) == [open.id])
}

@Test func duringTheWindowTheCardShowsInTheDestinationWhileTheTaskKeepsRunningWhereItWas() throws {
    let open = try OpenMove(running: true, to: \.testing)

    #expect(open.shown(in: \.testing) == [open.id])
    #expect(open.shown(in: \.doing).isEmpty)
    let task = try open.flow.current(open.id)
    #expect(task.stage == open.flow.doing)
    #expect(task.execution == .running)
    #expect(task.history.count == 1)
}

@Test func theWindowClosesAtFiveSecondsAndOnlyThenTheMoveCounts() throws {
    var open = try OpenMove(running: true, to: \.testing)

    #expect(open.window.close(at: seconds(4.9)) == nil)
    #expect(throws: WorkflowError.nothingToUndo) { try open.window.undo(at: seconds(5)) }
    let expired = open.window.close(at: seconds(5))
    try open.flow.board.complete(try #require(expired))

    let task = try open.flow.current(open.id)
    #expect(open.window.move == nil)
    #expect(task.stage == open.flow.testing)
    #expect(task.enteredStageAt == monday)
    #expect(task.execution == .idle)
    #expect(task.history.last == Movement(from: open.flow.doing, to: open.flow.testing, author: .user, at: monday))
}

@Test func movingAnotherTaskHandsBackTheOpenMoveToCompleteRightAway() throws {
    var open = try OpenMove(to: \.doing)
    let second = try open.flow.task()

    let displaced = try open.window.open(second, to: open.flow.testing, on: open.flow.board, at: seconds(2))

    #expect(displaced == UndoableMove(task: open.id, from: open.flow.backlog, to: open.flow.doing, at: monday))
    #expect(open.window.move == UndoableMove(task: second, from: open.flow.backlog, to: open.flow.testing,
                                             at: seconds(2)))
}

@Test func movingTheSameTaskAgainKeepsItsOriginAndRestartsTheWindow() throws {
    var open = try OpenMove(to: \.doing)

    #expect(try open.moveAgain(to: \.testing, at: seconds(4)) == nil)
    #expect(open.window.move == UndoableMove(task: open.id, from: open.flow.backlog, to: open.flow.testing,
                                             at: seconds(4)))
    #expect(try open.window.undo(at: seconds(8.9)).from == open.flow.backlog)
}

@Test func movingTheTaskBackToItsOriginCancelsTheMove() throws {
    var open = try OpenMove(to: \.doing)

    #expect(try open.moveAgain(to: \.backlog, at: seconds(1)) == nil)
    #expect(open.window.move == nil)
}

@Test func movingTheTaskAfterItsWindowRanOutStartsFromWhereThatMoveTookIt() throws {
    var open = try OpenMove(to: \.doing)
    var late = open

    let displaced = try open.moveAgain(to: \.testing, at: seconds(6))

    #expect(displaced?.to == open.flow.doing)
    #expect(open.window.move?.from == open.flow.doing)
    #expect(throws: WorkflowError.alreadyInStage) { try late.moveAgain(to: \.doing, at: seconds(6)) }
}

@Test func aMoveThatGoesNowhereNewOrToNothingDoesNotOpenTheWindow() throws {
    var open = try OpenMove(to: \.doing)
    var window = UndoWindow()
    let board = open.flow.board

    #expect(throws: WorkflowError.alreadyInStage) { try window.open(open.id, to: open.flow.backlog, on: board) }
    #expect(throws: WorkflowError.unknownStage) { try window.open(open.id, to: StageID(), on: board) }
    #expect(throws: WorkflowError.unknownTask) { try window.open(TaskID(), to: open.flow.doing, on: board) }
    #expect(throws: WorkflowError.alreadyInStage) { try open.moveAgain(to: \.doing, at: monday) }
    #expect(throws: WorkflowError.nothingToUndo) { try window.undo() }
}

@Test func aMoveWhoseTaskWasDeletedDuringTheWindowNoLongerApplies() throws {
    var open = try OpenMove(to: \.doing)

    try open.flow.board.deleteTask(open.id)
    let expired = open.window.close(at: seconds(5))
    let closed = try #require(expired)

    #expect(throws: WorkflowError.unknownTask) { try open.flow.board.complete(closed) }
}
