import Foundation
import SQLiteKit
import Workflow

extension SQLiteBoardRepository {
    private static let taskColumns = [
        "id", "project_id", "stage_id", "title", "details", "origin_app", "origin_key", "entered_stage_at",
        "execution", "agent_moves_in_a_row",
    ]

    @discardableResult
    static func deleteTasks(of project: ProjectID, in connection: Connection) throws -> Set<TaskID> {
        let ids = try connection.query("DELETE FROM tasks WHERE project_id = ? RETURNING id", [key(project)]) {
            UUID(uuidString: $0.text(0)).map(TaskID.init)
        }
        return Set(ids.compactMap(\.self))
    }

    static func insert(_ tasks: [BoardTask], of project: ProjectID, in connection: Connection) throws {
        let placeholders = Array(repeating: "?", count: taskColumns.count).joined(separator: ", ")
        let sql = "INSERT INTO tasks (\(taskColumns.joined(separator: ", "))) VALUES (\(placeholders))"
        for task in tasks {
            let values = record(of: task, in: project)
            try connection.execute(sql, taskColumns.map { values[$0] ?? .null })
            try insert(task.subtasks, of: task.id, in: connection)
        }
    }

    static func tasks(of project: ProjectID, in connection: Connection) throws -> [BoardTask] {
        let subtasks = try subtasks(of: project, in: connection)
        return try connection.query("""
            SELECT \(taskColumns.joined(separator: ", ")) FROM tasks WHERE project_id = ? ORDER BY rowid
            """, [key(project)]) { row in
            task(from: StoredRecord(row, columns: taskColumns), subtasks: subtasks)
        }.compactMap(\.self)
    }

    private static func record(of task: BoardTask, in project: ProjectID) -> [String: Value] {
        var values: [String: Value] = [
            "id": key(task.id),
            "project_id": key(project),
            "stage_id": key(task.stage),
            "title": .text(task.title),
            "details": .text(task.details),
            "entered_stage_at": .real(task.enteredStageAt.timeIntervalSince1970),
            "execution": .text(task.execution.stored),
            "agent_moves_in_a_row": .integer(Int64(task.agentMovesInARow)),
        ]
        if case .external(let app, let originKey) = task.origin {
            values["origin_app"] = .text(app)
            values["origin_key"] = .text(originKey)
        }
        return values
    }

    private static func task(from record: StoredRecord, subtasks: [TaskID: [Subtask]]) -> BoardTask? {
        guard let id = UUID(uuidString: record.text("id")).map(TaskID.init),
              let stage = UUID(uuidString: record.text("stage_id")),
              let execution = Execution(stored: record.text("execution")) else { return nil }
        return BoardTask(
            id: id,
            title: record.text("title"),
            details: record.text("details"),
            origin: origin(app: record["origin_app"], key: record["origin_key"]),
            stage: StageID(rawValue: stage),
            enteredStageAt: Date(timeIntervalSince1970: record["entered_stage_at"].realValue ?? 0),
            execution: execution,
            subtasks: subtasks[id] ?? [],
            agentMovesInARow: Int(record["agent_moves_in_a_row"].integerValue ?? 0)
        )
    }

    private static func origin(app: Value, key: Value) -> Origin {
        guard let app = app.textValue, let key = key.textValue else { return .den }
        return .external(app: app, key: key)
    }
}

struct StoredRecord {
    private let values: [String: Value]

    init(_ row: Row, columns: [String]) {
        values = Dictionary(uniqueKeysWithValues: columns.enumerated().map { ($1, row[$0]) })
    }

    subscript(_ column: String) -> Value {
        values[column] ?? .null
    }

    func text(_ column: String) -> String {
        self[column].textValue ?? ""
    }
}

extension Execution {
    var stored: String {
        switch self {
        case .idle: "idle"
        case .running: "running"
        case .finished: "finished"
        }
    }

    init?(stored: String) {
        switch stored {
        case "idle": self = .idle
        case "running": self = .running
        case "finished": self = .finished
        default: return nil
        }
    }
}
