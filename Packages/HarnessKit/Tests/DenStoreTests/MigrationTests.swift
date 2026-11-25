import Testing
import Foundation
import HarnessCore
@testable import DenStore
import SQLiteKit
import Workflow

extension ScratchStore {
    func olderStore(atVersion version: Int) throws -> Repositories {
        let database = try raw()
        try Migrator(Array(Schema.migrations.prefix(version))).migrate(database)
        return Repositories(database: database, now: { [clock] in clock.now })
    }
}

@Test func aVersionOneStoreMigratesWithoutLosingItsSessions() async throws {
    let scratch = try ScratchStore()
    defer { scratch.remove() }
    let session = try await saved(in: scratch.olderStore(atVersion: 1))

    let opened = try scratch.open()

    #expect(opened.setAside == nil)
    #expect(try await opened.repositories.sessions.list().map(\.id) == [session.id])
    #expect(try scratch.raw().read { try $0.query("PRAGMA user_version") { $0[0] } } == [.integer(3)])
    let columns = try scratch.raw().read {
        try $0.query("SELECT name FROM pragma_table_info('projects') ORDER BY cid") { $0[0].textValue ?? "" }
    }
    #expect(columns == ["id", "name", "root"])
}

@Test func aProjectFromAVersionTwoStoreCanKeepABoardAfterMigrating() throws {
    let scratch = try ScratchStore()
    defer { scratch.remove() }
    let project = try scratch.olderStore(atVersion: 2).boards
        .createProject(named: "Den", at: URL(filePath: "/tmp/den/repo"))
    var board = Board()
    try board.addStage(named: "Backlog")

    let boards = try scratch.open().repositories.boards
    try boards.save(board, of: project.id)

    #expect(try boards.projects().map(\.id) == [project.id])
    #expect(try boards.board(of: project.id) == board)
}
