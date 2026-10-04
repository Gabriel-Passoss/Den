import Testing
import Foundation
import SQLiteKit

private let steps = [
    "CREATE TABLE first (id INTEGER PRIMARY KEY)",
    "CREATE TABLE second (id INTEGER PRIMARY KEY)",
]

private let fullyMigrated: [Value] = [.integer(2), .text("first"), .text("second")]

private func versionAndTables(of database: Database) throws -> [Value] {
    try database.read {
        try $0.query("PRAGMA user_version") { $0[0] }
            + $0.query("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name") { $0[0] }
    }
}

@Test func aFreshDatabaseGetsEveryMigration() throws {
    let database = try Database(.memory)

    try Migrator(steps).migrate(database)

    #expect(try versionAndTables(of: database) == fullyMigrated)
}

@Test func migratingTwiceChangesNothing() throws {
    let database = try Database(.memory)
    let migrator = Migrator(steps)

    try migrator.migrate(database)
    try migrator.migrate(database)

    #expect(try versionAndTables(of: database) == fullyMigrated)
}

@Test func anOlderDatabaseOnlyGetsTheMigrationsItLacks() throws {
    let database = try Database(.memory)
    try Migrator([steps[0]]).migrate(database)
    #expect(try versionAndTables(of: database) == [.integer(1), .text("first")])

    try Migrator(steps).migrate(database)

    #expect(try versionAndTables(of: database) == fullyMigrated)
}

@Test func aNewerSchemaIsRefusedAndLeftAlone() throws {
    let database = try Database(.memory)
    try Migrator(steps).migrate(database)

    #expect(throws: DatabaseError.newerSchema(found: 2, supported: 1)) {
        try Migrator([steps[0]]).migrate(database)
    }
    #expect(try versionAndTables(of: database) == fullyMigrated)
}

@Test func aFailingMigrationLeavesTheVersionWhereItWas() throws {
    let database = try Database(.memory)
    let broken = [steps[0], steps[1] + "; CREATE TABLE first (again INTEGER)"]

    #expect(throws: DatabaseError.self) { try Migrator(broken).migrate(database) }

    #expect(try versionAndTables(of: database) == [.integer(1), .text("first")])
}
