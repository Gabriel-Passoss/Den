import Foundation
import SQLiteKit
import Workflow

extension SQLiteBoardRepository {
    private static let taskTable = StoredTable(name: "tasks", columns: [
        "id", "project_id", "stage_id", "title", "details", "origin_app", "origin_key", "entered_stage_at",
        "execution", "agent_moves_in_a_row", "session_id", "history", "pendencies",
    ])

    static func deleteTasks(of project: ProjectID, in connection: Connection) throws -> [TaskID: ChatID] {
        let links = try connection.query("""
            DELETE FROM tasks WHERE project_id = ? RETURNING id, session_id
            """, [key(project)]) { row -> (TaskID, ChatID)? in
            guard let task = UUID(uuidString: row.text(0)),
                  let chat = row[1].textValue.flatMap(UUID.init(uuidString:)) else { return nil }
            return (TaskID(rawValue: task), ChatID(rawValue: chat))
        }
        return Dictionary(uniqueKeysWithValues: links.compactMap(\.self))
    }

    static func deleteChats(of stored: [TaskID: ChatID], keeping board: Board, in connection: Connection) throws {
        let kept = Set(board.tasks.map(\.id))
        for (task, chat) in stored where !kept.contains(task) {
            try connection.execute("DELETE FROM sessions WHERE id = ?", [key(chat)])
        }
    }

    static func insert(_ tasks: [BoardTask], of project: ProjectID, in connection: Connection) throws {
        for task in tasks {
            try taskTable.insert(record(of: task, in: project), in: connection)
            try insert(task.subtasks, of: task.id, in: connection)
        }
    }

    static func tasks(of project: ProjectID, in connection: Connection) throws -> [BoardTask] {
        let subtasks = try subtasks(of: project, in: connection)
        return try connection.query("""
            SELECT \(taskTable.selection) FROM tasks WHERE project_id = ? ORDER BY rowid
            """, [key(project)]) { row in
            task(from: taskTable.record(row), subtasks: subtasks)
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
            "history": .text(TaskJournal.stored(task.history)),
            "pendencies": .text(TaskJournal.stored(task.pendencies)),
        ]
        if let chat = task.chat {
            values["session_id"] = key(chat)
        }
        if case .external(let app, let originKey) = task.origin {
            values["origin_app"] = .text(app)
            values["origin_key"] = .text(originKey)
        }
        return values
    }

    private static func task(from record: StoredRecord, subtasks: [TaskID: [Subtask]]) -> BoardTask? {
        guard let id: TaskID = record.id("id"), let stage: StageID = record.id("stage_id"),
              let execution = Execution(stored: record.text("execution")) else { return nil }
        return BoardTask(
            id: id,
            title: record.text("title"),
            details: record.text("details"),
            origin: origin(app: record["origin_app"], key: record["origin_key"]),
            stage: stage,
            enteredStageAt: Date(timeIntervalSince1970: record["entered_stage_at"].realValue ?? 0),
            execution: execution,
            subtasks: subtasks[id] ?? [],
            pendencies: TaskJournal.pendencies(from: record.text("pendencies")),
            history: TaskJournal.history(from: record.text("history")),
            agentMovesInARow: Int(record["agent_moves_in_a_row"].integerValue ?? 0),
            chat: record.id("session_id")
        )
    }

    private static func origin(app: Value, key: Value) -> Origin {
        guard let app = app.textValue, let key = key.textValue else { return .den }
        return .external(app: app, key: key)
    }
}
