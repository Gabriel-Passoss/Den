import Foundation
import HarnessCore
import SQLiteKit

public protocol SessionPreferencesRepository: Sendable {
    func preferences(for session: UUID) -> [String: String]

    func setPreferences(_ values: [String: String], for session: UUID) throws
}

struct SQLiteSessionPreferencesRepository: SessionPreferencesRepository {
    let database: Database

    func preferences(for session: UUID) -> [String: String] {
        let rows = try? database.read { connection in
            try connection.query("SELECT knob, value FROM session_preferences WHERE session_id = ?",
                                 [.text(session.uuidString)]) { ($0.text(0), $0.text(1)) }
        }
        return Dictionary(rows ?? [], uniquingKeysWith: { first, _ in first })
    }

    func setPreferences(_ values: [String: String], for session: UUID) throws {
        let key = Value.text(session.uuidString)
        try database.write { connection in
            guard try connection.hasSession(session) else {
                throw SessionRepositoryError.sessionNotFound(session)
            }
            try connection.execute("DELETE FROM session_preferences WHERE session_id = ?", [key])
            for (knob, value) in values {
                try connection.execute(
                    "INSERT INTO session_preferences (session_id, knob, value) VALUES (?, ?, ?)",
                    [key, .text(knob), .text(value)])
            }
        }
    }
}
