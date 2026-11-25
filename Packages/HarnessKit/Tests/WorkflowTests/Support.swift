import Testing
import Workflow
import WorkflowTestSupport

extension Flow {
    func current(_ id: TaskID) throws -> BoardTask {
        try #require(board.task(id))
    }

    func expectStillInDoing(_ id: TaskID, waitingOn kinds: [Pendency.Kind]) throws {
        let task = try current(id)
        #expect(task.stage == doing)
        #expect(task.execution == .finished)
        #expect(task.pendencies.map(\.kind) == kinds)
    }
}
