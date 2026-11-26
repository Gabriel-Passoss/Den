import Foundation
import SQLiteKit
import Workflow

extension Row {
    func text(_ column: Int) -> String { self[column].textValue ?? "" }

    func integer(_ column: Int) -> Int { Int(self[column].integerValue ?? 0) }

    func real(_ column: Int) -> Double { self[column].realValue ?? 0 }
}

struct StoredTable {
    let name: String
    let columns: [String]

    var selection: String {
        columns.map { "\(name).\($0)" }.joined(separator: ", ")
    }

    func insert(_ values: [String: Value], in connection: Connection) throws {
        let placeholders = Array(repeating: "?", count: columns.count).joined(separator: ", ")
        try connection.execute("INSERT INTO \(name) (\(columns.joined(separator: ", "))) VALUES (\(placeholders))",
                               columns.map { values[$0] ?? .null })
    }

    func record(_ row: Row) -> StoredRecord {
        StoredRecord(values: Dictionary(uniqueKeysWithValues: columns.enumerated().map { ($1, row[$0]) }))
    }
}

struct StoredRecord {
    let values: [String: Value]

    subscript(_ column: String) -> Value {
        values[column] ?? .null
    }

    func text(_ column: String) -> String {
        self[column].textValue ?? ""
    }

    func id<ID: WorkflowIdentifier>(_ column: String) -> ID? {
        self[column].textValue.flatMap(UUID.init(uuidString:)).map(ID.init(rawValue:))
    }
}

extension Connection {
    func hasSession(_ id: UUID) throws -> Bool {
        try !query("SELECT 1 FROM sessions WHERE id = ?", [.text(id.uuidString)]) { $0[0] }.isEmpty
    }
}
