import Testing
import Workflow
import WorkflowTestSupport

private let interrupted = Pendency.Kind.problem(.interrupted)

private func afterInterruption(_ tasks: (Flow) -> [BoardTask]) throws -> Board {
    let flow = try Flow()
    var board = Board(stages: flow.board.stages, tasks: tasks(flow))
    board.interruptRunningExecutions()
    return board
}

@Test func aTaskThatWasRunningComesBackIdleAndNeedingMe() throws {
    var flow = try Flow()
    let id = try flow.runningTask(in: flow.doing)

    flow.board.interruptRunningExecutions()

    let task = try flow.current(id)
    #expect(task.execution == .idle)
    #expect(task.pendencies.map(\.kind) == [interrupted])
    #expect(task.needsMe)
}

@Test func subagentsThatWereRunningComeBackIdleAndTheirTaskNeedsMe() throws {
    let board = try afterInterruption { flow in
        [BoardTask(title: "Exportar relatório", stage: flow.doing, enteredStageAt: monday, execution: .finished,
                   subtasks: [Subtask(title: "Tela", execution: .running), Subtask(title: "API", execution: .running)])]
    }

    #expect(board.tasks[0].execution == .finished)
    #expect(board.tasks[0].subtasks.map(\.execution) == [.idle, .idle])
    #expect(board.tasks[0].pendencies.map(\.kind) == [interrupted])
}

@Test func aTaskCutOffWithItsSubagentsGetsASingleWarningAndKeepsTheirProgress() throws {
    let board = try afterInterruption { flow in
        [BoardTask(title: "Exportar relatório", stage: flow.doing, enteredStageAt: monday, execution: .running,
                   subtasks: [
                       Subtask(title: "Tela", progress: .done, execution: .finished),
                       Subtask(title: "Botão", progress: .inProgress, execution: .running),
                       Subtask(title: "Arquivo", progress: .pending, execution: .running),
                   ],
                   pendencies: [Pendency(kind: .problem(.passageFailed))])]
    }

    let task = board.tasks[0]
    #expect(task.execution == .idle)
    #expect(task.subtasks.map(\.execution) == [.finished, .idle, .idle])
    #expect(task.subtasks.map(\.progress) == [.done, .inProgress, .pending])
    #expect(task.pendencies.map(\.kind) == [.problem(.passageFailed), interrupted])
}

@Test func aBoardWithNothingRunningIsLeftAsItWas() throws {
    let flow = try Flow()
    let tasks = [
        BoardTask(title: "Exportar relatório", stage: flow.doing, enteredStageAt: monday, execution: .finished,
                  subtasks: [Subtask(title: "Tela", progress: .inProgress, execution: .finished)]),
        BoardTask(title: "Corrigir login", stage: flow.backlog, enteredStageAt: tuesday,
                  subtasks: [Subtask(title: "Sessão")]),
    ]
    var board = Board(stages: flow.board.stages, tasks: tasks)

    board.interruptRunningExecutions()

    #expect(board == Board(stages: flow.board.stages, tasks: tasks))
}
