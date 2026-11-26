import Testing
import Workflow
import WorkflowTestSupport

@Test func aPassageIsTrimmedTextThatIsNotBlank() {
    #expect(Passage("  terminei a tela \n")?.text == "terminei a tela")
    #expect(Passage(" \n ") == nil)
}

@Test func movingBetweenTwoAgentStagesAwaitsAPassageFromTheOrigin() throws {
    var flow = try Flow()
    let id = try flow.task(in: flow.doing)
    try flow.board.moveTask(id, to: flow.testing)
    #expect(flow.board.awaitsPassage(id))

    let written = try #require(passage())
    try flow.board.recordPassage(written, for: id)

    #expect(try flow.current(id).history.last?.passage == written)
    #expect(!flow.board.awaitsPassage(id))
    #expect(throws: WorkflowError.noPassageAwaited) { try flow.board.recordPassage(written, for: id) }
}

@Test func noPassageIsAwaitedWithoutAnAgentOnBothEnds() throws {
    var flow = try Flow()
    let fromBacklog = try flow.task(in: flow.doing)
    let toDone = try flow.task(in: flow.doing)
    try flow.board.moveTask(toDone, to: flow.done)

    #expect(!flow.board.awaitsPassage(fromBacklog))
    #expect(!flow.board.awaitsPassage(toDone))
    #expect(!flow.board.awaitsPassage(try flow.task()))
    #expect(!flow.board.awaitsPassage(TaskID()))
}

@Test func noPassageIsAwaitedOnceTheNextAgentStarted() throws {
    var flow = try Flow()
    let id = try flow.task(in: flow.doing)
    try flow.board.moveTask(id, to: flow.testing)

    try flow.board.startExecution(of: id)

    #expect(!flow.board.awaitsPassage(id))
}

@Test func anAgentMoveAlreadyCarriesItsPassage() throws {
    var flow = try Flow()
    let id = try flow.runningTask(in: flow.doing)

    try flow.board.conclude(id, with: .move(to: flow.testing, passage: passage()))

    #expect(!flow.board.awaitsPassage(id))
}

@Test func aPassageForAnUnknownTaskFails() throws {
    var flow = try Flow()
    let written = try #require(passage())
    #expect(throws: WorkflowError.unknownTask) { try flow.board.recordPassage(written, for: TaskID()) }
}
