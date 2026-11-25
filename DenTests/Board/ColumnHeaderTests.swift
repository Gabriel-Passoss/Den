@testable import Den
import Testing
import Workflow
import WorkflowTestSupport

@Test func eachColumnCarriesItsStageNameAndHowManyTasksItHas() throws {
    var flow = try Flow()
    _ = try flow.task(in: flow.doing)
    _ = try flow.task(in: flow.doing)
    _ = try flow.task(in: flow.testing)

    let columns = BoardPresentation.display(of: flow.board).columns

    #expect(columns.map(\.name) == ["Backlog", "Em andamento", "Testes", "Pronto"])
    #expect(columns.map(\.taskCount) == [0, 2, 1, 0])
}

@Test func onlyTheFinalStageIsMarkedAsFinal() throws {
    let flow = try Flow()

    let columns = BoardPresentation.display(of: flow.board).columns

    #expect(columns.map(\.isFinal) == [false, false, false, true])
}

@Test func theFinalStageMarkIsLabelledForAccessibility() {
    #expect(ColumnDisplay.finalStageLabel == "Etapa final")
}
