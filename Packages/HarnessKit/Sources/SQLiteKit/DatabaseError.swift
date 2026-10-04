import SQLite3

public enum DatabaseError: Error, Equatable {
    case sqlite(code: Int32, message: String)
    case newerSchema(found: Int, supported: Int)

    public var isCorruption: Bool {
        guard case .sqlite(let code, _) = self else { return false }
        return code == SQLITE_CORRUPT || code == SQLITE_NOTADB
    }
}
