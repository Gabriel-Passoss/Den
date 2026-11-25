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

@Test func onlyTheRunningSubtaskOfAnActiveCardAnimates() throws {
    var flow = try Flow()
    let (id, running) = try flow.runningTaskWithSubtask()
    let waiting = try flow.board.addSubtask(titled: "API", to: id)
    try flow.board.startSubagent(for: running)

    #expect(try subtaskRow(running, of: id, on: flow.board).isAnimated)
    #expect(try !subtaskRow(waiting, of: id, on: flow.board).isAnimated)
}

@Test func aRunningSubtaskStaysStillOnACardThatNeedsMeOrFailed() throws {
    var flow = try Flow()
    let (asking, askingSubtask) = try flow.runningTaskWithSubtask()
    let (failing, failingSubtask) = try flow.runningTaskWithSubtask()
    try flow.board.startSubagent(for: askingSubtask)
    try flow.board.startSubagent(for: failingSubtask)
    try flow.board.openDecision(.permission, on: asking)
    try flow.board.reportProblem(.executionFailed("sem rede"), on: failing)

    for (subtask, task) in [(askingSubtask, asking), (failingSubtask, failing)] {
        let row = try subtaskRow(subtask, of: task, on: flow.board)
        #expect(row.status == .running)
        #expect(!row.isAnimated)
    }
}

private func subtaskRow(_ subtask: SubtaskID, of id: TaskID, on board: Board) throws -> SubtaskDisplay {
    try #require(card(id, on: board)?.subtaskRows.first { $0.id == subtask })
}

private func subtaskStatus(_ subtask: SubtaskID, of id: TaskID, on board: Board) throws -> TaskStatus {
    try subtaskRow(subtask, of: id, on: board).status
}
