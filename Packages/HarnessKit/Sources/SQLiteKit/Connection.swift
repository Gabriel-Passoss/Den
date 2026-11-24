import Foundation
import SQLite3

public struct Connection {
    let handle: OpaquePointer

    public var changes: Int { Int(sqlite3_changes(handle)) }

    public func execute(_ sql: String, _ bindings: [Value] = []) throws {
        _ = try query(sql, bindings) { _ in }
    }

    public func executeScript(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }

    public func query<T>(_ sql: String, _ bindings: [Value] = [],
                         _ map: (Row) throws -> T) throws -> [T] {
        var prepared: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &prepared, nil) == SQLITE_OK,
              let statement = prepared else { throw failure() }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        var rows: [T] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return rows }
            guard step == SQLITE_ROW else { throw failure() }
            try rows.append(map(Row(statement: statement)))
        }
    }

    func failure() -> DatabaseError {
        .sqlite(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)))
    }

    private func bind(_ values: [Value], to statement: OpaquePointer) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let code = switch value {
            case .null: sqlite3_bind_null(statement, index)
            case .integer(let number): sqlite3_bind_int64(statement, index, number)
            case .real(let number): sqlite3_bind_double(statement, index, number)
            case .text(let text): sqlite3_bind_text(statement, index, text, -1, transient)
            case .blob(let data): bind(data, to: statement, at: index, transient)
            }
            guard code == SQLITE_OK else { throw failure() }
        }
    }

    private func bind(_ data: Data, to statement: OpaquePointer, at index: Int32,
                      _ transient: sqlite3_destructor_type) -> Int32 {
        guard !data.isEmpty else { return sqlite3_bind_zeroblob(statement, index, 0) }
        return data.withUnsafeBytes {
            sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), transient)
        }
    }
}
