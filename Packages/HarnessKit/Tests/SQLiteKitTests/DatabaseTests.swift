import Testing
import Foundation
import SQLiteKit

private func notebook() throws -> Database {
    let database = try Database(.memory)
    try database.write { try $0.executeScript("CREATE TABLE notes (id INTEGER PRIMARY KEY, body)") }
    return database
}

private func bodies(in database: Database) throws -> [Value] {
    try database.read { try $0.query("SELECT body FROM notes ORDER BY id") { $0[0] } }
}

private func scratchFile() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "sqlitekit-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "notes.sqlite")
}

@Test func everyKindOfValueRoundTrips() throws {
    let database = try notebook()
    let values: [Value] = [.null, .integer(42), .real(1.5), .text("olá, 'mundo'"), .blob(Data([0, 1, 2]))]

    try database.write { connection in
        for value in values { try connection.execute("INSERT INTO notes (body) VALUES (?)", [value]) }
    }

    #expect(try bodies(in: database) == values)
}

@Test func anEmptyBlobComesBackEmptyRatherThanNull() throws {
    let database = try notebook()

    try database.write { try $0.execute("INSERT INTO notes (body) VALUES (?)", [.blob(Data())]) }

    #expect(try bodies(in: database) == [.blob(Data())])
}

@Test func aWriteReturnsItsBodysResultAndCommits() throws {
    let database = try notebook()

    let touched = try database.write { connection in
        try connection.execute("INSERT INTO notes (body) VALUES (?), (?)", [.text("a"), .text("b")])
        return connection.changes
    }

    #expect(touched == 2)
    #expect(try bodies(in: database) == [.text("a"), .text("b")])
}

@Test func aWriteThatThrowsLeavesNothingBehindAndTheDatabaseUsable() throws {
    struct Stop: Error {}
    let database = try notebook()

    #expect(throws: Stop.self) {
        try database.write { connection in
            try connection.execute("INSERT INTO notes (body) VALUES (?)", [.text("pela metade")])
            throw Stop()
        }
    }
    #expect(try bodies(in: database).isEmpty)

    try database.write { try $0.execute("INSERT INTO notes (body) VALUES (?)", [.text("inteira")]) }
    #expect(try bodies(in: database) == [.text("inteira")])
}

@Test func aScriptRunsEveryStatementInIt() throws {
    let database = try notebook()

    try database.write {
        try $0.executeScript("INSERT INTO notes (body) VALUES ('um'); INSERT INTO notes (body) VALUES ('dois')")
    }

    #expect(try bodies(in: database) == [.text("um"), .text("dois")])
}

@Test func foreignKeysAreEnforced() throws {
    let database = try Database(.memory)
    try database.write {
        try $0.executeScript("""
            CREATE TABLE parents (id INTEGER PRIMARY KEY);
            CREATE TABLE children (parent INTEGER NOT NULL REFERENCES parents(id));
            """)
    }

    #expect(throws: DatabaseError.self) {
        try database.write { try $0.execute("INSERT INTO children (parent) VALUES (?)", [.integer(7)]) }
    }
}

@Test func aBrokenStatementCarriesSQLitesCodeAndMessage() throws {
    let database = try notebook()

    do {
        try database.read { try $0.execute("SELEC nothing") }
        Issue.record("the statement should have failed")
    } catch DatabaseError.sqlite(let code, let message) {
        #expect(code == 1)
        #expect(message.contains("syntax error"))
    }
}

@Test func aBindingWithoutAPlaceholderFails() throws {
    let database = try notebook()

    #expect(throws: DatabaseError.self) {
        try database.read { try $0.execute("SELECT 1", [.integer(1)]) }
    }
    #expect(throws: DatabaseError.self) {
        try database.read { try $0.executeScript("SELEC nothing") }
    }
}

@Test func aFileDatabaseKeepsItsRowsAcrossInstancesAndRunsInWAL() throws {
    let file = try scratchFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

    do {
        let first = try Database(.file(file))
        try first.write {
            try $0.executeScript("CREATE TABLE notes (id INTEGER PRIMARY KEY, body)")
            try $0.execute("INSERT INTO notes (body) VALUES (?)", [.text("guardada")])
        }
    }
    let second = try Database(.file(file))

    #expect(try bodies(in: second) == [.text("guardada")])
    #expect(try second.read { try $0.query("PRAGMA journal_mode") { $0[0] } } == [.text("wal")])
    #expect(try second.read { try $0.query("PRAGMA foreign_keys") { $0[0] } } == [.integer(1)])
}

@Test func aFileThatIsNotADatabaseFailsAsCorruption() throws {
    let file = try scratchFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    try Data("isto não é um banco de dados, de jeito nenhum".utf8).write(to: file)

    do {
        _ = try Database(.file(file))
        Issue.record("opening should have failed")
    } catch let error as DatabaseError {
        #expect(error.isCorruption)
    }
}

@Test func aPathThatCannotHoldAFileFailsWithoutBeingCorruption() throws {
    let file = try scratchFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

    do {
        _ = try Database(.file(file.appending(path: "dentro/de/nada.sqlite")))
        Issue.record("opening should have failed")
    } catch let error as DatabaseError {
        #expect(!error.isCorruption)
    }
}

@Test func onlyCorruptionCodesCountAsCorruption() {
    #expect(DatabaseError.sqlite(code: 11, message: "").isCorruption)
    #expect(DatabaseError.sqlite(code: 26, message: "").isCorruption)
    #expect(!DatabaseError.sqlite(code: 1, message: "").isCorruption)
    #expect(!DatabaseError.newerSchema(found: 2, supported: 1).isCorruption)
}

@Test func aValueOnlyReadsAsItsOwnKind() {
    #expect(Value.text("a").textValue == "a")
    #expect(Value.integer(1).textValue == nil)
    #expect(Value.integer(7).integerValue == 7)
    #expect(Value.text("7").integerValue == nil)
    #expect(Value.real(1.5).realValue == 1.5)
    #expect(Value.integer(2).realValue == 2)
    #expect(Value.null.realValue == nil)
}

@Test func writersOnDifferentThreadsLoseNothing() async throws {
    let database = try notebook()

    try await withThrowingTaskGroup(of: Void.self) { group in
        for writer in 0..<8 {
            group.addTask {
                for round in 0..<50 {
                    try database.write {
                        try $0.execute("INSERT INTO notes (body) VALUES (?)", [.text("\(writer)-\(round)")])
                    }
                }
            }
        }
        try await group.waitForAll()
    }

    #expect(try bodies(in: database).count == 400)
}
