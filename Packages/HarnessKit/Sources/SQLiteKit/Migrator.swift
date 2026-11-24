public struct Migrator: Sendable {
    private let migrations: [String]

    public init(_ migrations: [String]) {
        self.migrations = migrations
    }

    public func migrate(_ database: Database) throws {
        while try applyNext(to: database) > 0 {}
    }

    private func applyNext(to database: Database) throws -> Int {
        try database.write { connection in
            let found = try connection.query("PRAGMA user_version") { Int($0[0].integerValue ?? 0) }.first ?? 0
            guard found <= migrations.count else {
                throw DatabaseError.newerSchema(found: found, supported: migrations.count)
            }
            guard let next = migrations.dropFirst(found).first else { return 0 }
            try connection.executeScript(next)
            try connection.executeScript("PRAGMA user_version = \(found + 1)")
            return migrations.count - found
        }
    }
}
