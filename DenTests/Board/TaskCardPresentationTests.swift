@testable import Den
import Testing
import Workflow
import WorkflowTestSupport

@Test func theCardCountsTheConcludedSubtasksAgainstTheTotal() throws {
    var flow = try Flow()
    let (id, first) = try flow.runningTaskWithSubtask()
    let second = try flow.board.addSubtask(titled: "API", to: id)
    try flow.board.addSubtask(titled: "Testes", to: id)
    try flow.board.setProgress(.done, of: first)
    try flow.board.setProgress(.inProgress, of: second)

    let progress = try #require(card(id, on: flow.board)?.subtasks)

    #expect(progress.done == 1)
    #expect(progress.total == 3)
    #expect(progress.label == "1/3")
}

@Test func aTaskWithoutSubtasksHasNoProgress() throws {
    var flow = try Flow()
    let id = try flow.task(in: flow.doing)

    #expect(card(id, on: flow.board)?.subtasks == nil)
}

@Test func theCardCarriesTheTitleAndNoKeyUntilTheTaskHasOne() throws {
    var flow = try Flow()
    let id = try flow.task(in: flow.doing)

    let display = try #require(card(id, on: flow.board))

    #expect(display.title == "Exportar relatório")
    #expect(display.key.isEmpty)
}

@Test func theCardsOfAStageKeepTheDomainOrder() throws {
    let flow = try Flow()
    let older = BoardTask(title: "Antiga", stage: flow.doing, enteredStageAt: monday)
    let newer = BoardTask(title: "Nova", stage: flow.doing, enteredStageAt: tuesday)
    let board = Board(stages: flow.board.stages, tasks: [newer, older])

    let doing = try #require(BoardPresentation.display(of: board).columns.first { $0.id == flow.doing })

    #expect(doing.cards.map(\.title) == ["Antiga", "Nova"])
}
