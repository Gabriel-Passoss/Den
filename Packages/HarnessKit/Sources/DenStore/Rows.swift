import Foundation
import SQLiteKit

extension Row {
    func text(_ column: Int) -> String { self[column].textValue ?? "" }

    func integer(_ column: Int) -> Int { Int(self[column].integerValue ?? 0) }

    func real(_ column: Int) -> Double { self[column].realValue ?? 0 }
}

extension Connection {
    func hasSession(_ id: UUID) throws -> Bool {
        try !query("SELECT 1 FROM sessions WHERE id = ?", [.text(id.uuidString)]) { $0[0] }.isEmpty
    }
}
