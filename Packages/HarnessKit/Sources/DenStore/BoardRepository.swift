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

    func save(_ board: Board, of project: ProjectID) throws
}

struct SQLiteBoardRepository: BoardRepository {
    private static let stageTable = StoredTable(name: "stages", columns: [
        "id", "project_id", "position", "name", "agent", "is_final",
    ])

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

    func board(of project: ProjectID) throws -> Board {
        var board = try database.read { connection in
            Board(stages: try Self.stages(of: project, in: connection),
                  tasks: try Self.tasks(of: project, in: connection))
        }
        board.interruptRunningExecutions()
        return board
    }

    func save(_ board: Board, of project: ProjectID) throws {
        try database.write { connection in
            let stored = try Self.deleteTasks(of: project, in: connection)
            try Self.deleteChats(of: stored, keeping: board, in: connection)
            try connection.execute("DELETE FROM stages WHERE project_id = ?", [Self.key(project)])
            try Self.insert(board.stages, of: project, in: connection)
            try Self.insert(board.tasks, of: project, in: connection)
        }
    }

    private static func stages(of project: ProjectID, in connection: Connection) throws -> [Stage] {
        try connection.query("""
            SELECT \(stageTable.selection) FROM stages WHERE project_id = ? ORDER BY position
            """, [key(project)]) { row in
            let record = stageTable.record(row)
            let id: StageID? = record.id("id")
            return id.map {
                Stage(id: $0, name: record.text("name"), agent: record["agent"].textValue.map(AgentID.init),
                      isFinal: record["is_final"] == .integer(1))
            }
        }.compactMap(\.self)
    }

    private static func insert(_ stages: [Stage], of project: ProjectID, in connection: Connection) throws {
        for (position, stage) in stages.enumerated() {
            try stageTable.insert([
                "id": key(stage.id),
                "project_id": key(project),
                "position": .integer(Int64(position)),
                "name": .text(stage.name),
                "agent": stage.agent.map { .text($0.rawValue) } ?? .null,
                "is_final": .integer(stage.isFinal ? 1 : 0),
            ], in: connection)
        }
    }

    static func key(_ id: some WorkflowIdentifier) -> Value {
        .text(id.rawValue.uuidString)
    }

    private static func directory(at path: String) -> URL {
        URL(filePath: path, directoryHint: .isDirectory)
    }
}
