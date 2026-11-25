import Testing
import Workflow

@Test func theRunningAgentCreatesSubtasks() throws {
    var flow = try Flow()
    let id = try flow.runningTask(in: flow.doing)

    let subtask = try flow.board.addSubtask(titled: " Tela de exportação ", to: id)

    #expect(try flow.current(id).subtasks == [Subtask(id: subtask, title: "Tela de exportação")])
    #expect(try flow.current(id).hasOpenSubtasks)
    #expect(throws: WorkflowError.blankName) { try flow.board.addSubtask(titled: "", to: id) }
}

@Test func noSubtaskIsCreatedWithoutARunningAgent() throws {
    var flow = try Flow()
    let id = try flow.task(in: flow.doing)
    #expect(throws: WorkflowError.executionNotRunning) { try flow.board.addSubtask(titled: "Tela", to: id) }
    #expect(throws: WorkflowError.unknownTask) { try flow.board.addSubtask(titled: "Tela", to: TaskID()) }
}

@Test func progressGoesFromAnyStateToAnyOther() throws {
    var flow = try Flow()
    let id = try flow.runningTask(in: flow.doing)
    let subtask = try flow.board.addSubtask(titled: "Tela", to: id)

    for progress in [SubtaskProgress.done, .pending, .inProgress, .done] {
        try flow.board.setProgress(progress, of: subtask)
        #expect(try flow.current(id).subtasks.map(\.progress) == [progress])
    }
    #expect(try !flow.current(id).hasOpenSubtasks)
}

@Test func progressOnlyChangesWhileTheMainAgentRuns() throws {
    var flow = try Flow()
    let id = try flow.runningTask(in: flow.doing)
    let subtask = try flow.board.addSubtask(titled: "Tela", to: id)
    try flow.board.endExecution(of: id)

    #expect(throws: WorkflowError.executionNotRunning) { try flow.board.setProgress(.done, of: subtask) }
    #expect(throws: WorkflowError.executionNotRunning) { try flow.board.startSubagent(for: subtask) }
    #expect(throws: WorkflowError.unknownSubtask) { try flow.board.setProgress(.done, of: SubtaskID()) }
}

@Test func aSubagentRunsOnceAtATime() throws {
    var flow = try Flow()
    let id = try flow.runningTask(in: flow.doing)
    let subtask = try flow.board.addSubtask(titled: "Tela", to: id)

    try flow.board.startSubagent(for: subtask)
    #expect(try flow.current(id).subtasks.map(\.execution) == [.running])
    #expect(throws: WorkflowError.executionAlreadyRunning) { try flow.board.startSubagent(for: subtask) }

    try flow.board.endSubagent(for: subtask)
    #expect(try flow.current(id).subtasks.map(\.execution) == [.finished])
    #expect(throws: WorkflowError.executionNotRunning) { try flow.board.endSubagent(for: subtask) }
    #expect(throws: WorkflowError.unknownSubtask) { try flow.board.endSubagent(for: SubtaskID()) }
}

@Test func aFailedSubagentBecomesAProblemOnTheParent() throws {
    var flow = try Flow()
    let id = try flow.runningTask(in: flow.doing)
    let subtask = try flow.board.addSubtask(titled: "Tela", to: id)
    try flow.board.startSubagent(for: subtask)
    try flow.board.setProgress(.inProgress, of: subtask)

    try flow.board.reportProblem(.subagentFailed(subtask), on: id)
    try flow.board.endSubagent(for: subtask)

    let task = try flow.current(id)
    #expect(task.needsMe)
    #expect(task.pendencies.map(\.kind) == [.problem(.subagentFailed(subtask))])
    #expect(task.subtasks.map(\.progress) == [.inProgress])
}
