import Testing
import Foundation
import DenStore
import Workflow

private let repo = URL(filePath: "/tmp/den/repo", directoryHint: .isDirectory)

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
