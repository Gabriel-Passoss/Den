import Testing
import Workflow
import WorkflowTestSupport

@Test func onlyAStageWithAnAgentRunsATask() throws {
    var flow = try Flow()
    let id = try flow.task()

    #expect(throws: WorkflowError.stageHasNoAgent) { try flow.board.startExecution(of: id) }
    try flow.board.moveTask(id, to: flow.doing)
    try flow.board.startExecution(of: id)

    #expect(try flow.current(id).execution == .running)
    #expect(throws: WorkflowError.executionAlreadyRunning) { try flow.board.startExecution(of: id) }
    #expect(throws: WorkflowError.unknownTask) { try flow.board.startExecution(of: TaskID()) }
}

@Test func runningTheAgentAgainClosesWhatWaitedForTheUserButKeepsProblems() throws {
    var flow = try Flow()
    let (id, problem) = try flow.taskWaitingWithAProblem()

    try flow.board.startExecution(of: id)

    #expect(try flow.current(id).pendencies.map(\.id) == [problem])
}

@Test func endingAnExecutionDropsItsDecisionsAndStopsItsSubagents() throws {
    var flow = try Flow()
    let id = try flow.runningTask(in: flow.doing)
    let subtask = try flow.board.addSubtask(titled: "API", to: id)
    try flow.board.startSubagent(for: subtask)
    try flow.board.openDecision(.question, on: id)

    try flow.board.endExecution(of: id)

    let task = try flow.current(id)
    #expect(task.execution == .finished)
    #expect(task.subtasks.map(\.execution) == [.finished])
    #expect(!task.needsMe)
    #expect(throws: WorkflowError.executionNotRunning) { try flow.board.endExecution(of: id) }
}

@Test func aDecisionIsOnlyAskedWhileTheAgentRuns() throws {
    var flow = try Flow()
    let id = try flow.task(in: flow.doing)
    #expect(throws: WorkflowError.executionNotRunning) { try flow.board.openDecision(.permission, on: id) }
}

@Test func anOpenDecisionNeedsMeUntilIAnswerIt() throws {
    var flow = try Flow()
    let id = try flow.runningTask(in: flow.doing)

    let decision = try flow.board.openDecision(.permission, on: id)
    #expect(try flow.current(id).needsMe)
    #expect(try flow.current(id).pendencies == [Pendency(id: decision, kind: .decision(.permission))])

    try flow.board.answerDecision(decision)
    #expect(try !flow.current(id).needsMe)
    #expect(throws: WorkflowError.unknownPendency) { try flow.board.answerDecision(decision) }
}

@Test func onlyADecisionIsAnswered() throws {
    var flow = try Flow()
    let id = try flow.task()
    let problem = try flow.board.reportProblem(.passageFailed, on: id)

    #expect(throws: WorkflowError.notADecision) { try flow.board.answerDecision(problem) }
    #expect(try flow.current(id).needsMe)
}

@Test func aProblemNeedsMeUntilItIsResolved() throws {
    var flow = try Flow()
    let id = try flow.task()
    let first = try flow.board.reportProblem(.passageFailed, on: id)
    let second = try flow.board.reportProblem(.executionFailed("chave inválida"), on: id)

    try flow.board.resolve(first)

    #expect(try flow.current(id).pendencies == [Pendency(id: second, kind: .problem(.executionFailed("chave inválida")))])
    #expect(throws: WorkflowError.unknownPendency) { try flow.board.resolve(first) }
    #expect(throws: WorkflowError.unknownTask) { try flow.board.reportProblem(.passageFailed, on: TaskID()) }
}

@Test func anyUserActionResetsTheChainOfAgentMoves() throws {
    var flow = try Flow()
    let id = try flow.runningTask(in: flow.doing)
    try flow.board.conclude(id, with: .move(to: flow.testing, passage: passage()))
    #expect(try flow.current(id).agentMovesInARow == 1)
    try flow.board.registerUserAction(on: id)
    #expect(try flow.current(id).agentMovesInARow == 0)

    try agentMove(&flow, id, to: flow.doing)
    try flow.board.startExecution(of: id)
    try flow.board.answerDecision(try flow.board.openDecision(.question, on: id))
    #expect(try flow.current(id).agentMovesInARow == 0)

    try agentMove(&flow, id, to: flow.testing)
    try flow.board.resolve(try flow.board.reportProblem(.passageFailed, on: id))
    #expect(try flow.current(id).agentMovesInARow == 0)

    try agentMove(&flow, id, to: flow.doing)
    try flow.board.moveTask(id, to: flow.backlog)
    #expect(try flow.current(id).agentMovesInARow == 0)
    #expect(throws: WorkflowError.unknownTask) { try flow.board.registerUserAction(on: TaskID()) }
}

private func agentMove(_ flow: inout Flow, _ id: TaskID, to stage: StageID) throws {
    if try flow.current(id).execution != .running { try flow.board.startExecution(of: id) }
    try flow.board.conclude(id, with: .move(to: stage, passage: passage()))
    #expect(try flow.current(id).agentMovesInARow == 1)
}
