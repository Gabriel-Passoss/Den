import Foundation
import SQLiteKit

public struct SidebarFolder: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct SidebarLayout: Sendable, Equatable {
    public var folders: [SidebarFolder]
    public var membership: [UUID: String]
    public var order: [UUID]

    public init(folders: [SidebarFolder] = [], membership: [UUID: String] = [:], order: [UUID] = []) {
        self.folders = folders
        self.membership = membership
        self.order = order
    }
}

public protocol SidebarRepository: Sendable {
    func load() throws -> SidebarLayout

    func save(_ layout: SidebarLayout) throws
}

struct SQLiteSidebarRepository: SidebarRepository {
    let database: Database

    func load() throws -> SidebarLayout {
        try database.read { connection in
            let folders = try connection.query("SELECT id, name FROM folders ORDER BY position") {
                SidebarFolder(id: $0.text(0), name: $0.text(1))
            }
            let placed = try connection.query(
                "SELECT id, folder_id FROM sessions WHERE folder_id IS NOT NULL") { ($0.text(0), $0.text(1)) }
            let ordered = try connection.query(
                "SELECT id FROM sessions WHERE position IS NOT NULL ORDER BY position") { $0.text(0) }
            var membership: [UUID: String] = [:]
            for (session, folder) in placed {
                if let id = UUID(uuidString: session) { membership[id] = folder }
            }
            return SidebarLayout(folders: folders, membership: membership,
                                 order: ordered.compactMap { UUID(uuidString: $0) })
        }
    }

    func save(_ layout: SidebarLayout) throws {
        let kept = layout.folders.map { Value.text($0.id) }
        let placeholders = Array(repeating: "?", count: kept.count).joined(separator: ", ")
        try database.write { connection in
            try connection.execute("DELETE FROM folders WHERE id NOT IN (\(placeholders))", kept)
            for (position, folder) in layout.folders.enumerated() {
                try connection.execute("""
                    INSERT INTO folders (id, name, position) VALUES (?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET name = excluded.name, position = excluded.position
                    """, [.text(folder.id), .text(folder.name), .integer(Int64(position))])
            }
            try connection.execute("UPDATE sessions SET folder_id = NULL, position = NULL")
            for (session, folder) in layout.membership {
                try connection.execute("""
                    UPDATE sessions SET folder_id = ?
                    WHERE id = ? AND EXISTS (SELECT 1 FROM folders WHERE id = ?)
                    """, [.text(folder), .text(session.uuidString), .text(folder)])
            }
            for (position, session) in layout.order.enumerated() {
                try connection.execute("UPDATE sessions SET position = ? WHERE id = ?",
                                       [.integer(Int64(position)), .text(session.uuidString)])
            }
        }
    }
}
