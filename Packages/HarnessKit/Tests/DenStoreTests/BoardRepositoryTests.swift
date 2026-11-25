import Testing
import Foundation
import DenStore
import SQLiteKit
import Workflow
import WorkflowTestSupport

private let repo = URL(filePath: "/tmp/den/repo", directoryHint: .isDirectory)

private func denProject(in boards: any BoardRepository) throws -> Project {
    try boards.createProject(named: "Den", at: repo)
}

@Test func aCreatedProjectIsListed() throws {
    let boards = try DenStore.inMemory().boards

    let project = try boards.createProject(named: "Den", at: repo)

    #expect(project.name == "Den")
    #expect(project.root == repo)
    #expect(try boards.projects() == [project])
}

@Test func theFolderIsStandardizedBeforeItIsKept() throws {
    let boards = try DenStore.inMemory().boards

    let project = try boards.createProject(named: "Den", at: URL(filePath: "/tmp/den/./outro/../repo"))

    #expect(project.root.path == "/tmp/den/repo")
    #expect(try boards.projects().map(\.root.path) == ["/tmp/den/repo"])
}

@Test func aFolderThatIsAlreadyAProjectIsRefused() throws {
    let boards = try DenStore.inMemory().boards
    let first = try boards.createProject(named: "Den", at: repo)

    #expect(throws: BoardRepositoryError.projectAlreadyExists) {
        try boards.createProject(named: "Outro nome", at: URL(filePath: "/tmp/den/outro/../repo/"))
    }

    #expect(try boards.projects() == [first])
}

@Test func projectsAreListedByName() throws {
    let boards = try DenStore.inMemory().boards
    let zeta = try boards.createProject(named: "Zeta", at: URL(filePath: "/tmp/zeta"))
    let alpha = try boards.createProject(named: "Alpha", at: URL(filePath: "/tmp/alpha"))

    #expect(try boards.projects() == [alpha, zeta])
}

@Test func aNewProjectHasAnEmptyBoard() throws {
    let boards = try DenStore.inMemory().boards

    let project = try boards.createProject(named: "Den", at: repo)

    #expect(try boards.board(of: project.id) == Board())
}

@Test func aProjectSurvivesReopeningTheStore() throws {
    let scratch = try ScratchStore()
    defer { scratch.remove() }
    let project = try scratch.open().repositories.boards.createProject(named: "Den", at: repo)

    let boards = try scratch.open().repositories.boards

    #expect(try boards.projects() == [project])
    #expect(try boards.board(of: project.id) == Board())
}

@Test func savedStagesComeBackAfterReopeningTheStore() throws {
    let scratch = try ScratchStore()
    defer { scratch.remove() }
    let boards = try scratch.open().repositories.boards
    let project = try boards.createProject(named: "Den", at: repo)
    let flow = try Flow()

    try boards.save(flow.board, of: project.id)

    let stages = try scratch.open().repositories.boards.board(of: project.id).stages
    #expect(stages.map(\.name) == ["Backlog", "Em andamento", "Testes", "Pronto"])
    #expect(stages.map(\.agent) == [nil, implementer, tester, nil])
    #expect(stages.map(\.isFinal) == [false, false, false, true])
    #expect(stages.map(\.id) == [flow.backlog, flow.doing, flow.testing, flow.done])
}

@Test func savingAgainReplacesTheBoardThatWasThere() throws {
    let boards = try DenStore.inMemory().boards
    let project = try boards.createProject(named: "Den", at: repo)
    var flow = try Flow()
    try boards.save(flow.board, of: project.id)

    try flow.board.removeStage(flow.testing)
    try flow.board.renameStage(flow.doing, to: "Implementação")
    try flow.board.moveStage(flow.done, toPosition: 0)
    try flow.board.assignAgent(nil, to: flow.doing)
    try boards.save(flow.board, of: project.id)

    let stages = try boards.board(of: project.id).stages
    #expect(stages.map(\.id) == [flow.done, flow.backlog, flow.doing])
    #expect(stages.map(\.name) == ["Pronto", "Backlog", "Implementação"])
    #expect(stages.map(\.agent) == [nil, nil, nil])
}

@Test func eachProjectKeepsItsOwnBoard() throws {
    let boards = try DenStore.inMemory().boards
    let den = try boards.createProject(named: "Den", at: repo)
    let other = try boards.createProject(named: "Outro", at: URL(filePath: "/tmp/outro"))
    let flow = try Flow()
    var small = Board()
    try small.addStage(named: "Só uma")

    try boards.save(flow.board, of: den.id)
    try boards.save(small, of: other.id)

    #expect(try boards.board(of: den.id) == flow.board)
    #expect(try boards.board(of: other.id) == small)
}

@Test func aSaveThatFailsHalfwayKeepsTheBoardThatWasThere() throws {
    let boards = try DenStore.inMemory().boards
    let project = try boards.createProject(named: "Den", at: repo)
    let flow = try Flow()
    try boards.save(flow.board, of: project.id)
    let repeated = Stage(name: "Repetida")

    #expect(throws: (any Error).self) {
        try boards.save(Board(stages: [Stage(name: "Nova"), repeated, repeated]), of: project.id)
    }

    #expect(try boards.board(of: project.id) == flow.board)
}

@Test func savedTasksComeBackInTheirStagesAfterReopeningTheStore() throws {
    let scratch = try ScratchStore()
    defer { scratch.remove() }
    let boards = try scratch.open().repositories.boards
    let project = try denProject(in: boards)
    let flow = try Flow()
    let board = Board(stages: flow.board.stages, tasks: [
        BoardTask(title: "Exportar relatório", details: "em CSV", stage: flow.backlog, enteredStageAt: monday),
        BoardTask(title: "Corrigir login", origin: .external(app: "jira", key: "DEN-7"), stage: flow.doing,
                  enteredStageAt: Date(timeIntervalSince1970: 1_234.5), execution: .running, agentMovesInARow: 2),
        BoardTask(title: "Revisar textos", stage: flow.testing, enteredStageAt: tuesday, execution: .finished),
        BoardTask(title: "Publicar", origin: .external(app: "jira", key: "DEN-8"), stage: flow.done,
                  enteredStageAt: wednesday),
    ])

    try boards.save(board, of: project.id)

    #expect(try scratch.open().repositories.boards.board(of: project.id) == board)
}

@Test func aTaskRemovedFromTheBoardIsGoneAfterTheNextSave() throws {
    let boards = try DenStore.inMemory().boards
    let project = try denProject(in: boards)
    var flow = try Flow()
    let kept = try flow.task(in: flow.doing)
    let removed = try flow.task(at: tuesday)
    try boards.save(flow.board, of: project.id)

    try flow.board.deleteTask(removed)
    try boards.save(flow.board, of: project.id)

    #expect(try boards.board(of: project.id).tasks.map(\.id) == [kept])
}

@Test func theSameExternalOriginTwiceInAProjectIsRefused() throws {
    let boards = try DenStore.inMemory().boards
    let project = try denProject(in: boards)
    var flow = try Flow()
    try boards.save(flow.board, of: project.id)
    let jira = Origin.external(app: "jira", key: "DEN-7")
    try flow.board.createTask(titled: "Corrigir login", origin: jira, at: monday)
    try flow.board.createTask(titled: "Corrigir login de novo", origin: jira, at: tuesday)

    #expect(throws: (any Error).self) { try boards.save(flow.board, of: project.id) }

    #expect(try boards.board(of: project.id).tasks.isEmpty)
}

@Test func theSameExternalOriginCanBeInTwoProjects() throws {
    let boards = try DenStore.inMemory().boards
    let den = try boards.createProject(named: "Den", at: repo)
    let other = try boards.createProject(named: "Outro", at: URL(filePath: "/tmp/outro"))
    var first = try Flow()
    var second = try Flow()
    try first.board.createTask(titled: "Corrigir login", origin: .external(app: "jira", key: "DEN-7"), at: monday)
    try second.board.createTask(titled: "Corrigir login", origin: .external(app: "jira", key: "DEN-7"), at: monday)

    try boards.save(first.board, of: den.id)
    try boards.save(second.board, of: other.id)

    #expect(try boards.board(of: den.id) == first.board)
    #expect(try boards.board(of: other.id) == second.board)
}

@Test func deletingAProjectTakesItsTasksAlong() throws {
    let scratch = try ScratchStore()
    defer { scratch.remove() }
    let boards = try scratch.open().repositories.boards
    let project = try denProject(in: boards)
    var flow = try Flow()
    _ = try flow.task(in: flow.doing)
    try boards.save(flow.board, of: project.id)

    try scratch.raw().write {
        try $0.execute("DELETE FROM projects WHERE id = ?", [.text(project.id.rawValue.uuidString)])
    }

    #expect(try scratch.raw().read { try $0.query("SELECT count(*) FROM tasks") { $0[0] } } == [.integer(0)])
}
