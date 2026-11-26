import Testing
import Workflow
import WorkflowTestSupport

@Test func theAppTestsBuildARealBoardWithTheSharedSupport() throws {
    var flow = try Flow()

    let (id, _) = try flow.taskWaitingWithAProblem()

    #expect(flow.board.stages.map(\.name) == ["Backlog", "Em andamento", "Testes", "Pronto"])
    #expect(flow.board.task(id)?.needsMe == true)
}
