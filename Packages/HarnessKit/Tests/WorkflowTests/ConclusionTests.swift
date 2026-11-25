import Testing
import Workflow

@Test func anAgentWithoutADecisionLeavesTheTaskWaitingForMe() throws {
    var flow = try Flow()
    let id = try flow.runningTask(in: flow.doing)

    #expect(try flow.board.conclude(id, with: .undecided) == .waitingForUser)

    try flow.expectStillInDoing(id, waitingOn: [.stageFinished])
}

@Test func anAgentReturnsTheTaskToMeWithItsPassage() throws {
    var flow = try Flow()
    let id = try flow.runningTask(in: flow.doing)
    let written = try #require(passage("parei: a API de pagamento está fora"))

    #expect(try flow.board.conclude(id, with: .returnToUser(written)) == .waitingForUser)

    #expect(try flow.current(id).pendencies.map(\.kind) == [.returned(written)])
}

@Test func returningWithoutAPassageIsRefused() throws {
    var flow = try Flow()
    let id = try flow.runningTask(in: flow.doing)

    #expect(try flow.board.conclude(id, with: .returnToUser(nil)) == .refused(.missingPassage))

    #expect(try flow.current(id).pendencies.map(\.kind) == [.problem(.moveRefused(.missingPassage))])
}

@Test func anAgentMovesTheTaskWithItsPassage() throws {
    var flow = try Flow()
    let id = try flow.runningTask(in: flow.doing)
    let written = try #require(passage())

    #expect(try flow.board.conclude(id, with: .move(to: flow.testing, passage: written), at: tuesday) == .moved)

    let task = try flow.current(id)
    #expect(task.stage == flow.testing)
    #expect(task.enteredStageAt == tuesday)
    #expect(task.execution == .idle)
    #expect(!task.needsMe)
    #expect(task.history.last == Movement(from: flow.doing, to: flow.testing, author: .agent(implementer),
                                          at: tuesday, passage: written))
}

@Test(arguments: [(MoveRefusal.unknownStage, true), (.sameStage, true), (.missingPassage, false)])
func anAgentMoveTheBoardCannotTakeBecomesAProblem(refusal: MoveRefusal, withPassage: Bool) throws {
    var flow = try Flow()
    let id = try flow.runningTask(in: flow.doing)
    let destination = switch refusal {
    case .unknownStage: StageID()
    case .sameStage: flow.doing
    default: flow.testing
    }

    let outcome = try flow.board.conclude(id, with: .move(to: destination, passage: withPassage ? passage() : nil))

    #expect(outcome == .refused(refusal))
    try flow.expectStillInDoing(id, waitingOn: [.problem(.moveRefused(refusal))])
}

@Test func anAgentCannotConcludeATaskWithOpenSubtasks() throws {
    var flow = try Flow()
    let id = try flow.runningTask(in: flow.doing)
    let finished = try flow.board.addSubtask(titled: "API", to: id)
    let open = try flow.board.addSubtask(titled: "Tela", to: id)
    try flow.board.setProgress(.done, of: finished)

    #expect(try flow.board.conclude(id, with: .move(to: flow.done, passage: passage())) == .refused(.openSubtasks))
    #expect(!flow.board.isConcluded(id))

    try flow.board.startExecution(of: id)
    try flow.board.setProgress(.done, of: open)
    #expect(try flow.board.conclude(id, with: .move(to: flow.done, passage: passage())) == .moved)
    #expect(flow.board.isConcluded(id))
}

@Test func theUserMayConcludeATaskWithOpenSubtasks() throws {
    var flow = try Flow()
    let id = try flow.runningTask(in: flow.doing)
    try flow.board.addSubtask(titled: "Tela", to: id)

    try flow.board.moveTask(id, to: flow.done)

    #expect(flow.board.isConcluded(id))
}

@Test func theChainLimitStopsAgentsFromMovingATaskForever() throws {
    var flow = try Flow()
    let id = try flow.runningTask(in: flow.doing)
    let limit = ChainLimit(moves: 2)
    let written = try #require(passage())

    #expect(try flow.board.conclude(id, with: .move(to: flow.testing, passage: written), chainLimit: limit) == .moved)
    try flow.board.startExecution(of: id)
    #expect(try flow.board.conclude(id, with: .move(to: flow.doing, passage: written), chainLimit: limit) == .moved)
    try flow.board.startExecution(of: id)
    #expect(try flow.board.conclude(id, with: .move(to: flow.testing, passage: written), chainLimit: limit)
        == .chainLimitReached)

    let task = try flow.current(id)
    #expect(task.stage == flow.doing)
    #expect(task.history.count == 3)
    #expect(task.pendencies.map(\.kind) == [.chainLimitReached(destination: flow.testing, passage: written)])
}

@Test func theChainLimitIsAtLeastOneMoveAndFiveByDefault() {
    #expect(ChainLimit.standard.moves == 5)
    #expect(ChainLimit(moves: 0).moves == 1)
    #expect(ChainLimit(moves: 3).moves == 3)
}

@Test func onlyARunningAgentConcludes() throws {
    var flow = try Flow()
    let idle = try flow.task(in: flow.doing)
    let unassigned = try flow.runningTask(in: flow.testing)
    try flow.board.assignAgent(nil, to: flow.testing)

    #expect(throws: WorkflowError.executionNotRunning) { try flow.board.conclude(idle, with: .undecided) }
    #expect(throws: WorkflowError.stageHasNoAgent) { try flow.board.conclude(unassigned, with: .undecided) }
    #expect(try flow.current(unassigned).execution == .running)
}
