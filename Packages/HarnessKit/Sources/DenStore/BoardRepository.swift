import Foundation
import SQLiteKit
import Workflow

public enum BoardRepositoryError: Error, Equatable {
    case projectAlreadyExists
}

public protocol BoardRepository: Sendable {
    func createProject(named name: String, at root: URL) throws -> Project

    func projects() throws -> [Project]

    func board(of project: ProjectID) throws -> Board
}

struct SQLiteBoardRepository: BoardRepository {
    let database: Database

    func createProject(named name: String, at root: URL) throws -> Project {
        let path = root.standardizedFileURL.path
        let project = Project(name: name, root: Self.directory(at: path))
        try database.write { connection in
            let taken = try connection.query("SELECT 1 FROM projects WHERE root = ?", [.text(path)]) { $0[0] }
            guard taken.isEmpty else { throw BoardRepositoryError.projectAlreadyExists }
            try connection.execute("INSERT INTO projects (id, name, root) VALUES (?, ?, ?)",
                                   [.text(project.id.rawValue.uuidString), .text(name), .text(path)])
        }
        return project
    }

    func projects() throws -> [Project] {
        try database.read { connection in
            try connection.query("SELECT id, name, root FROM projects ORDER BY name, root") { row in
                UUID(uuidString: row.text(0)).map {
                    Project(id: ProjectID(rawValue: $0), name: row.text(1), root: Self.directory(at: row.text(2)))
                }
            }.compactMap(\.self)
        }
    }

    func board(of _: ProjectID) throws -> Board {
        Board()
    }

    private static func directory(at path: String) -> URL {
        URL(filePath: path, directoryHint: .isDirectory)
    }
}
