import Testing
import Foundation
import HarnessCore
import DenStore
import Workflow
import WorkflowTestSupport

private func chat(of session: Session) -> ChatID {
    ChatID(rawValue: session.id)
}

private func linked(to session: Session, titled title: String = "Exportar relatório", in flow: Flow) -> BoardTask {
    BoardTask(title: title, stage: flow.backlog, enteredStageAt: monday, chat: chat(of: session))
}

private func denProject(in repositories: Repositories) throws -> ProjectID {
    try repositories.boards.createProject(named: "Den", at: URL(filePath: "/tmp/den/repo")).id
}

@Test func aTaskKeepsItsChatAfterReopeningTheStore() async throws {
    let scratch = try ScratchStore()
    defer { scratch.remove() }
    let repositories = try scratch.open().repositories
    let project = try denProject(in: repositories)
    let session = try await saved(in: repositories)
    let flow = try Flow()

    try repositories.boards.save(Board(stages: flow.board.stages, tasks: [linked(to: session, in: flow)]),
                                 of: project)

    #expect(try scratch.open().repositories.boards.board(of: project).tasks.map(\.chat) == [chat(of: session)])
}

@Test func aTaskWithoutAChatComesBackWithoutOne() throws {
    let scratch = try ScratchStore()
    defer { scratch.remove() }
    let repositories = try scratch.open().repositories
    let project = try denProject(in: repositories)
    var flow = try Flow()
    _ = try flow.task()

    try repositories.boards.save(flow.board, of: project)

    #expect(try scratch.open().repositories.boards.board(of: project).tasks.map(\.chat) == [nil])
}

@Test func removingATaskAndSavingDeletesItsChat() async throws {
    let repositories = try DenStore.inMemory()
    let project = try denProject(in: repositories)
    let removed = try await saved(conversation("da task removida"), in: repositories)
    let kept = try await saved(conversation("da task que fica"), in: repositories)
    let flow = try Flow()
    let staying = linked(to: kept, titled: "Fica", in: flow)
    try repositories.boards.save(
        Board(stages: flow.board.stages, tasks: [staying, linked(to: removed, titled: "Sai", in: flow)]), of: project
    )

    try repositories.boards.save(Board(stages: flow.board.stages, tasks: [staying]), of: project)

    #expect(try await repositories.sessions.list().map(\.id) == [kept.id])
    #expect(try repositories.boards.board(of: project).tasks.map(\.chat) == [chat(of: kept)])
}

@Test func deletingAChatKeepsItsTaskWithoutALink() async throws {
    let repositories = try DenStore.inMemory()
    let project = try denProject(in: repositories)
    let session = try await saved(in: repositories)
    let flow = try Flow()
    let task = linked(to: session, in: flow)
    try repositories.boards.save(Board(stages: flow.board.stages, tasks: [task]), of: project)

    try await repositories.sessions.delete(session.id)

    let tasks = try repositories.boards.board(of: project).tasks
    #expect(tasks.map(\.id) == [task.id])
    #expect(tasks.map(\.chat) == [nil])
}
