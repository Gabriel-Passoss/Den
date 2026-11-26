@testable import Den
import Testing
import Workflow
import WorkflowTestSupport

@Test func aTaskWithTwoPendenciesCountsOnceAmongTheTasksThatNeedMe() throws {
    var flow = try Flow()
    let (twice, _) = try flow.taskWaitingWithAProblem()
    let decided = try flow.runningTask(in: flow.testing)
    _ = try flow.board.openDecision(.question, on: decided)
    _ = try flow.runningTask(in: flow.doing)

    #expect(try #require(flow.board.task(twice)).pendencies.count == 2)
    #expect(BoardPresentation.display(of: flow.board).needsMeCount == 2)
}

@Test func aBoardWithNothingPendingNeedsMeForNothing() throws {
    var flow = try Flow()
    _ = try flow.runningTask(in: flow.doing)
    _ = try flow.task()

    #expect(BoardPresentation.display(of: flow.board).needsMeCount == 0)
    #expect(BoardPresentation.display(of: Board()).needsMeCount == 0)
}

@Test func theCounterDisappearsWhenNothingNeedsMe() {
    #expect(BoardPresentation.needsMeLabel(0) == nil)
}

@Test func theCounterSpeaksInTheSingularForOneTaskAndInThePluralForSeveral() {
    #expect(BoardPresentation.needsMeLabel(1) == "1 precisa de você")
    #expect(BoardPresentation.needsMeLabel(3) == "3 precisam de você")
}
