import Foundation
import Testing
import Workflow
import WorkflowTestSupport

@Test func aTaskNeedsAStageToLandIn() {
    var board = Board()
    #expect(throws: WorkflowError.boardHasNoStages) { try board.createTask(titled: "Exportar relatório") }
}

@Test func aNewTaskLandsInTheFirstStage() throws {
    var flow = try Flow()
    try flow.board.moveStage(flow.doing, toPosition: 0)

    let id = try flow.board.createTask(titled: " Exportar relatório ", details: "CSV e PDF", at: monday)

    #expect(try flow.current(id) == BoardTask(id: id, title: "Exportar relatório", details: "CSV e PDF",
                                              stage: flow.doing, enteredStageAt: monday))
    #expect(try !flow.current(id).needsMe)
}

@Test func aTaskKeepsWhereItCameFrom() throws {
    var flow = try Flow()
    let id = try flow.board.createTask(titled: "Corrigir login", origin: .external(app: "Jira", key: "NS-42"))
    #expect(try flow.current(id).origin == .external(app: "Jira", key: "NS-42"))
}

@Test func aTaskNeedsATitleThatIsNotBlank() throws {
    var flow = try Flow()
    #expect(throws: WorkflowError.blankName) { try flow.board.createTask(titled: " ") }
    #expect(flow.board.tasks.isEmpty)
}

@Test func aDeletedTaskLeavesTheBoard() throws {
    var flow = try Flow()
    let kept = try flow.task()
    let deleted = try flow.runningTask(in: flow.doing)

    try flow.board.deleteTask(deleted)

    #expect(flow.board.tasks.map(\.id) == [kept])
    #expect(throws: WorkflowError.unknownTask) { try flow.board.deleteTask(deleted) }
}

@Test func theUserMovesATaskToAnyStageAndTheMoveIsRecorded() throws {
    var flow = try Flow()
    let id = try flow.task(at: monday)

    try flow.board.moveTask(id, to: flow.testing, at: tuesday)
    try flow.board.moveTask(id, to: flow.doing, at: wednesday)

    let task = try flow.current(id)
    #expect(task.stage == flow.doing)
    #expect(task.enteredStageAt == wednesday)
    #expect(task.history == [
        Movement(from: flow.backlog, to: flow.testing, author: .user, at: tuesday),
        Movement(from: flow.testing, to: flow.doing, author: .user, at: wednesday),
    ])
}

@Test func movingATaskWhereItAlreadyIsOrToNowhereFails() throws {
    var flow = try Flow()
    let id = try flow.task()

    #expect(throws: WorkflowError.alreadyInStage) { try flow.board.moveTask(id, to: flow.backlog) }
    #expect(throws: WorkflowError.unknownStage) { try flow.board.moveTask(id, to: StageID()) }
    #expect(throws: WorkflowError.unknownTask) { try flow.board.moveTask(TaskID(), to: flow.doing) }
    #expect(try flow.current(id).history.isEmpty)
}

@Test func movingATaskEndsItsExecutionAndItsSubagentsWithoutTouchingProgress() throws {
    var flow = try Flow()
    let id = try flow.runningTask(in: flow.doing)
    let subtask = try flow.board.addSubtask(titled: "Tela", to: id)
    try flow.board.setProgress(.inProgress, of: subtask)
    try flow.board.startSubagent(for: subtask)
    try flow.board.openDecision(.permission, on: id)

    try flow.board.moveTask(id, to: flow.testing)

    let task = try flow.current(id)
    #expect(task.execution == .idle)
    #expect(task.subtasks.map(\.execution) == [.idle])
    #expect(task.subtasks.map(\.progress) == [.inProgress])
    #expect(task.pendencies.isEmpty)
}

@Test func movingATaskClosesWhatWaitedForTheUserButKeepsProblems() throws {
    var flow = try Flow()
    let (id, problem) = try flow.taskWaitingWithAProblem()

    try flow.board.moveTask(id, to: flow.testing)

    #expect(try flow.current(id).pendencies.map(\.id) == [problem])
}

@Test func tasksThatNeedMeComeFirstThenTheOldest() throws {
    var flow = try Flow()
    let newest = try flow.task(in: flow.doing, at: wednesday)
    let oldest = try flow.task(in: flow.doing, at: monday)
    let middle = try flow.task(in: flow.doing, at: tuesday)
    let stuckLate = try flow.task(in: flow.doing, at: wednesday)
    let stuckEarly = try flow.task(in: flow.doing, at: tuesday)
    _ = try flow.task(in: flow.testing, at: monday)
    try flow.board.reportProblem(.passageFailed, on: stuckLate)
    try flow.board.reportProblem(.passageFailed, on: stuckEarly)

    #expect(flow.board.tasks(in: flow.doing).map(\.id) == [stuckEarly, stuckLate, oldest, middle, newest])
}

@Test func aTaskInAFinalStageIsConcluded() throws {
    var flow = try Flow()
    let id = try flow.task(in: flow.testing)
    #expect(!flow.board.isConcluded(id))

    try flow.board.moveTask(id, to: flow.done)
    #expect(flow.board.isConcluded(id))
    #expect(!flow.board.isConcluded(TaskID()))
}
