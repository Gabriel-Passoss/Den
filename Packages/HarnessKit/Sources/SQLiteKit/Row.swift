import Foundation
import SQLite3

public struct Row {
    let statement: OpaquePointer

    public subscript(_ column: Int) -> Value {
        let index = Int32(column)
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            return .text(sqlite3_column_text(statement, index).map { String(cString: $0) } ?? "")
        case SQLITE_BLOB:
            let bytes = sqlite3_column_blob(statement, index)
            let count = Int(sqlite3_column_bytes(statement, index))
            return .blob(bytes.map { Data(bytes: $0, count: count) } ?? Data())
        default:
            return .null
        }
    }
}
