import Testing
import Workflow

@Test func aNewBoardHasNoStagesAndNoTasks() {
    let board = Board()
    #expect(board.stages.isEmpty)
    #expect(board.tasks.isEmpty)
}

@Test func stagesKeepTheOrderTheyWereAddedInWithTrimmedNames() throws {
    var board = Board()
    let first = try board.addStage(named: "  Backlog \n")
    let second = try board.addStage(named: "Revisão", agent: tester, isFinal: true)

    #expect(board.stages.map(\.id) == [first, second])
    #expect(board.stage(first) == Stage(id: first, name: "Backlog"))
    #expect(board.stage(second) == Stage(id: second, name: "Revisão", agent: tester, isFinal: true))
}

@Test func aStageNeedsANameThatIsNotBlank() throws {
    var board = Board()
    #expect(throws: WorkflowError.blankName) { try board.addStage(named: "  ") }

    let stage = try board.addStage(named: "Backlog")
    #expect(throws: WorkflowError.blankName) { try board.renameStage(stage, to: "\n") }
    #expect(board.stage(stage)?.name == "Backlog")
}

@Test func aStageCanBeRenamedReassignedAndMarkedFinal() throws {
    var board = Board()
    let stage = try board.addStage(named: "Testes")

    try board.renameStage(stage, to: " Validação ")
    try board.assignAgent(tester, to: stage)
    try board.markFinal(true, stage: stage)
    #expect(board.stage(stage) == Stage(id: stage, name: "Validação", agent: tester, isFinal: true))

    try board.assignAgent(nil, to: stage)
    try board.markFinal(false, stage: stage)
    #expect(board.stage(stage) == Stage(id: stage, name: "Validação"))
}

@Test func reorderingStagesClampsThePositionAndMovesNoTask() throws {
    var flow = try Flow()
    let task = try flow.task(in: flow.testing)

    try flow.board.moveStage(flow.done, toPosition: 0)
    #expect(flow.board.stages.map(\.id) == [flow.done, flow.backlog, flow.doing, flow.testing])

    try flow.board.moveStage(flow.done, toPosition: 99)
    #expect(flow.board.stages.map(\.id) == [flow.backlog, flow.doing, flow.testing, flow.done])

    try flow.board.moveStage(flow.testing, toPosition: -3)
    #expect(flow.board.stages.map(\.id) == [flow.testing, flow.backlog, flow.doing, flow.done])

    try flow.board.moveStage(flow.testing, toPosition: 2)
    #expect(flow.board.stages.map(\.id) == [flow.backlog, flow.doing, flow.testing, flow.done])
    #expect(try flow.current(task).stage == flow.testing)
}

@Test func onlyAnEmptyStageCanBeRemoved() throws {
    var flow = try Flow()
    _ = try flow.task(in: flow.doing)

    #expect(throws: WorkflowError.stageHasTasks) { try flow.board.removeStage(flow.doing) }
    try flow.board.removeStage(flow.testing)
    #expect(flow.board.stages.map(\.id) == [flow.backlog, flow.doing, flow.done])
}

@Test func removingTheLastEmptyStageLeavesTheBoardAsItStarted() throws {
    var board = Board()
    let only = try board.addStage(named: "Backlog")

    try board.removeStage(only)

    #expect(board == Board())
}

@Test func editingAStageThatIsNotOnTheBoardFails() throws {
    var board = Board()
    let ghost = StageID()

    #expect(throws: WorkflowError.unknownStage) { try board.renameStage(ghost, to: "x") }
    #expect(throws: WorkflowError.unknownStage) { try board.moveStage(ghost, toPosition: 0) }
    #expect(throws: WorkflowError.unknownStage) { try board.assignAgent(tester, to: ghost) }
    #expect(throws: WorkflowError.unknownStage) { try board.markFinal(true, stage: ghost) }
    #expect(throws: WorkflowError.unknownStage) { try board.removeStage(ghost) }
    #expect(board.stage(ghost) == nil)
}

@Test func theOrderSuggestsTheNextStageWithoutRequiringIt() throws {
    let flow = try Flow()

    #expect(flow.board.suggestedStage(after: flow.backlog) == flow.doing)
    #expect(flow.board.suggestedStage(after: flow.testing) == flow.done)
    #expect(flow.board.suggestedStage(after: flow.done) == nil)
    #expect(flow.board.suggestedStage(after: StageID()) == nil)
}
