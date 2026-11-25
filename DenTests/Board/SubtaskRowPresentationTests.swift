@testable import Den
import Testing
import Workflow
import WorkflowTestSupport

@Test func aSubtaskNamedByASubagentProblemOfItsTaskFailed() throws {
    var flow = try Flow()
    let (id, failing) = try flow.runningTaskWithSubtask()
    let other = try flow.board.addSubtask(titled: "API", to: id)
    try flow.board.reportProblem(.subagentFailed(failing), on: id)

    #expect(try subtaskStatus(failing, of: id, on: flow.board) == .failed)
    #expect(try subtaskStatus(other, of: id, on: flow.board) == .notStarted)
}

@Test func aFailedSubtaskStaysFailedWhileItsSubagentRunsAndAfterItsProgressIsDone() throws {
    var flow = try Flow()
    let (id, failing) = try flow.runningTaskWithSubtask()
    try flow.board.startSubagent(for: failing)
    try flow.board.setProgress(.done, of: failing)
    try flow.board.reportProblem(.subagentFailed(failing), on: id)

    #expect(try subtaskStatus(failing, of: id, on: flow.board) == .failed)
}

@Test func aSubtaskWhoseProgressIsDoneIsConcludedEvenWithItsSubagentRunning() throws {
    var flow = try Flow()
    let (id, subtask) = try flow.runningTaskWithSubtask()
    try flow.board.startSubagent(for: subtask)
    try flow.board.setProgress(.done, of: subtask)

    #expect(try subtaskStatus(subtask, of: id, on: flow.board) == .concluded)
}

@Test func aSubtaskWhoseSubagentRunsIsRunning() throws {
    var flow = try Flow()
    let (id, subtask) = try flow.runningTaskWithSubtask()
    try flow.board.startSubagent(for: subtask)

    #expect(try subtaskStatus(subtask, of: id, on: flow.board) == .running)
}

@Test func aSubtaskInProgressWithoutARunningSubagentHasNotStarted() throws {
    var flow = try Flow()
    let (id, subtask) = try flow.runningTaskWithSubtask()
    try flow.board.setProgress(.inProgress, of: subtask)

    #expect(try subtaskStatus(subtask, of: id, on: flow.board) == .notStarted)
}

@Test func anotherKindOfProblemDoesNotFailTheSubtask() throws {
    var flow = try Flow()
    let (id, subtask) = try flow.runningTaskWithSubtask()
    try flow.board.reportProblem(.executionFailed("sem rede"), on: id)

    #expect(try subtaskStatus(subtask, of: id, on: flow.board) == .notStarted)
}

@Test func theRowsKeepTheSubtaskOrderAndCarryTheirTitles() throws {
    var flow = try Flow()
    let (id, first) = try flow.runningTaskWithSubtask()
    let second = try flow.board.addSubtask(titled: "API", to: id)

    let rows = try #require(card(id, on: flow.board)).subtaskRows

    #expect(rows.map(\.id) == [first, second])
    #expect(rows.map(\.title) == ["Tela", "API"])
}

@Test func aTaskWithoutSubtasksHasNoRows() throws {
    var flow = try Flow()
    let id = try flow.task(in: flow.doing)

    #expect(try #require(card(id, on: flow.board)).subtaskRows.isEmpty)
}

private func subtaskStatus(_ subtask: SubtaskID, of id: TaskID, on board: Board) throws -> TaskStatus {
    try #require(card(id, on: board)?.subtaskRows.first { $0.id == subtask }).status
}
