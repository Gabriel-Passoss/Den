import Testing
import Foundation
import HarnessCore
@testable import DenStore
import SQLiteKit

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
    #expect(try scratch.raw().read { try $0.query("PRAGMA user_version") { $0[0] } } == [.integer(2)])
    let columns = try scratch.raw().read {
        try $0.query("SELECT name FROM pragma_table_info('projects') ORDER BY cid") { $0[0].textValue ?? "" }
    }
    #expect(columns == ["id", "name", "root"])
}
