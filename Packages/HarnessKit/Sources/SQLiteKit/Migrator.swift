public struct Migrator: Sendable {
    private let migrations: [String]

    public init(_ migrations: [String]) {
        self.migrations = migrations
    }

    public func migrate(_ database: Database) throws {
        let found = try database.read { connection in
            try connection.query("PRAGMA user_version") { Int($0[0].integerValue ?? 0) }.first ?? 0
        }
        guard found <= migrations.count else {
            throw DatabaseError.newerSchema(found: found, supported: migrations.count)
        }
        for index in found..<migrations.count {
            try database.write { connection in
                try connection.executeScript(migrations[index])
                try connection.executeScript("PRAGMA user_version = \(index + 1)")
            }
        }
    }
}
