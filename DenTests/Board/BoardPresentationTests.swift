@testable import Den
import Testing
import Workflow
import WorkflowTestSupport

@Test func theColumnsFollowTheBoardAndTheCardsFollowTheDomainOrder() throws {
    var flow = try Flow()
    let older = try flow.task(in: flow.doing, at: monday)
    let newer = try flow.task(in: flow.doing, at: tuesday)
    let (waiting, _) = try flow.taskWaitingWithAProblem()

    let columns = BoardPresentation.columns(for: flow.board)

    #expect(columns.map(\.id) == [flow.backlog, flow.doing, flow.testing, flow.done])
    #expect(columns[1].cards.map(\.id) == [waiting, older, newer])
    #expect(columns[0].cards.isEmpty)
}

@Test func aTaskThatNeverRanHasNotStartedAndOneWhoseExecutionEndedIsStopped() throws {
    var flow = try Flow()
    let fresh = try flow.task(in: flow.doing)
    let ended = try flow.runningTask(in: flow.doing)
    try flow.board.endExecution(of: ended)

    #expect(status(of: fresh, on: flow.board) == .notStarted)
    #expect(status(of: ended, on: flow.board) == .stopped)
}

@Test func aTaskWhoseExecutionIsGoingOnIsRunning() throws {
    var flow = try Flow()
    let id = try flow.runningTask(in: flow.doing)

    #expect(status(of: id, on: flow.board) == .running)
}

private func card(_ id: TaskID, on board: Board) -> CardDisplay? {
    BoardPresentation.columns(for: board).flatMap(\.cards).first { $0.id == id }
}

private func status(of id: TaskID, on board: Board) -> TaskStatus? {
    card(id, on: board)?.status
}

@Test func aProblemMakesTheTaskFailEvenWhenItAlsoNeedsMe() throws {
    var flow = try Flow()
    let (id, _) = try flow.taskWaitingWithAProblem()

    #expect(status(of: id, on: flow.board) == .failed)
}

@Test func aPendencyThatIsNotAProblemNeedsMe() throws {
    var flow = try Flow()
    let id = try flow.runningTask(in: flow.doing)
    try flow.board.conclude(id, with: .undecided)

    #expect(status(of: id, on: flow.board) == .needsMe)
}

@Test func aDecisionOpenedDuringTheExecutionNeedsMeInsteadOfRunning() throws {
    var flow = try Flow()
    let id = try flow.runningTask(in: flow.doing)
    try flow.board.openDecision(.permission, on: id)

    #expect(status(of: id, on: flow.board) == .needsMe)
    #expect(card(id, on: flow.board)?.isActive == false)
}

@Test func aTaskInTheFinalStageIsConcludedEvenAfterItsExecutionEnded() throws {
    var flow = try Flow()
    let untouched = try flow.task(in: flow.done)
    let ended = try flow.runningTask(in: flow.doing)
    try flow.board.endExecution(of: ended)
    try flow.board.moveTask(ended, to: flow.done)

    #expect(status(of: untouched, on: flow.board) == .concluded)
    #expect(status(of: ended, on: flow.board) == .concluded)
}

@Test func aTaskStillRunningInAStageMarkedFinalIsRunning() throws {
    var flow = try Flow()
    let id = try flow.runningTask(in: flow.doing)
    try flow.board.markFinal(true, stage: flow.doing)

    #expect(status(of: id, on: flow.board) == .running)
}

@Test func aProblemInTheFinalStageFailsInsteadOfConcluding() throws {
    var flow = try Flow()
    let id = try flow.runningTask(in: flow.doing)
    try flow.board.reportProblem(.executionFailed("sem rede"), on: id)
    try flow.board.markFinal(true, stage: flow.doing)

    #expect(status(of: id, on: flow.board) == .failed)
}

@Test func aSubagentStillRunningKeepsTheTaskActiveAfterItsExecutionEnded() throws {
    let flow = try Flow()
    let task = BoardTask(title: "Exportar relatório", stage: flow.doing, enteredStageAt: monday,
                         execution: .finished, subtasks: [Subtask(title: "Tela", execution: .running)])
    let board = Board(stages: flow.board.stages, tasks: [task])

    #expect(status(of: task.id, on: board) == .running)
    #expect(card(task.id, on: board)?.isActive == true)
}

@Test func eachStatusReadsInPortuguese() {
    #expect(TaskStatus.failed.label == "Falhou")
    #expect(TaskStatus.needsMe.label == "Precisa de você")
    #expect(TaskStatus.running.label == "Em execução")
    #expect(TaskStatus.concluded.label == "Concluído")
    #expect(TaskStatus.stopped.label == "Parada")
    #expect(TaskStatus.notStarted.label == "Não iniciada")
}
