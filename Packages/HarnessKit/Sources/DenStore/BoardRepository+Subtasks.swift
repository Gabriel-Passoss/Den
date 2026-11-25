import Foundation
import SQLiteKit
import Workflow

extension SQLiteBoardRepository {
    static func insert(_ subtasks: [Subtask], of task: TaskID, in connection: Connection) throws {
        for (position, subtask) in subtasks.enumerated() {
            try connection.execute("""
                INSERT INTO subtasks (id, task_id, position, title, progress, execution) VALUES (?, ?, ?, ?, ?, ?)
                """, [
                    key(subtask.id), key(task), .integer(Int64(position)), .text(subtask.title),
                    .text(subtask.progress.stored), .text(subtask.execution.stored),
                ])
        }
    }

    static func subtasks(of project: ProjectID, in connection: Connection) throws -> [TaskID: [Subtask]] {
        let rows = try connection.query("""
            SELECT subtasks.task_id, subtasks.id, subtasks.title, subtasks.progress, subtasks.execution
            FROM subtasks JOIN tasks ON tasks.id = subtasks.task_id
            WHERE tasks.project_id = ? ORDER BY subtasks.task_id, subtasks.position
            """, [key(project)]) { row -> (TaskID, Subtask)? in
            guard let task = UUID(uuidString: row.text(0)), let id = UUID(uuidString: row.text(1)),
                  let progress = SubtaskProgress(stored: row.text(3)),
                  let execution = Execution(stored: row.text(4)) else { return nil }
            let subtask = Subtask(id: SubtaskID(rawValue: id), title: row.text(2), progress: progress,
                                  execution: execution)
            return (TaskID(rawValue: task), subtask)
        }
        return Dictionary(grouping: rows.compactMap(\.self), by: \.0).mapValues { $0.map(\.1) }
    }
}

extension SubtaskProgress {
    var stored: String {
        switch self {
        case .pending: "pending"
        case .inProgress: "in_progress"
        case .done: "done"
        }
    }

    init?(stored: String) {
        switch stored {
        case "pending": self = .pending
        case "in_progress": self = .inProgress
        case "done": self = .done
        default: return nil
        }
    }
}
