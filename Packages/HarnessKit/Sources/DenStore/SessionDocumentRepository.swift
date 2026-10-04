import Foundation
import HarnessCore
import SQLiteKit

public protocol SessionDocumentRepository<Value>: Sendable {
    associatedtype Value: Codable & Sendable

    func all() -> [UUID: Value]

    func save(_ value: Value, for session: UUID) throws

    func remove(_ session: UUID) throws
}

struct SQLiteSessionDocumentRepository<Document: Codable & Sendable>: SessionDocumentRepository {
    let database: Database
    let kind: String

    func all() -> [UUID: Document] {
        let rows = try? database.read { connection in
            try connection.query("SELECT session_id, payload FROM session_documents WHERE kind = ?",
                                 [.text(kind)]) { ($0.text(0), $0.text(1)) }
        }
        var documents: [UUID: Document] = [:]
        for (session, payload) in rows ?? [] {
            guard let id = UUID(uuidString: session),
                  let document = JSONText.decode(Document.self, from: payload, as: .document) else { continue }
            documents[id] = document
        }
        return documents
    }

    func save(_ value: Document, for session: UUID) throws {
        let payload = try JSONText.encode(value, as: .document)
        try database.write { connection in
            guard try connection.hasSession(session) else {
                throw SessionRepositoryError.sessionNotFound(session)
            }
            try connection.execute("""
                INSERT INTO session_documents (session_id, kind, payload) VALUES (?, ?, ?)
                ON CONFLICT(session_id, kind) DO UPDATE SET payload = excluded.payload
                """, [.text(session.uuidString), .text(kind), .text(payload)])
        }
    }

    func remove(_ session: UUID) throws {
        try database.write { connection in
            try connection.execute("DELETE FROM session_documents WHERE session_id = ? AND kind = ?",
                                   [.text(session.uuidString), .text(kind)])
        }
    }
}
