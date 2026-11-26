import Foundation
import SQLiteKit
import Workflow

extension SQLiteBoardRepository {
    private static let subtaskTable = StoredTable(name: "subtasks", columns: [
        "id", "task_id", "position", "title", "progress", "execution",
    ])

    static func insert(_ subtasks: [Subtask], of task: TaskID, in connection: Connection) throws {
        for (position, subtask) in subtasks.enumerated() {
            try subtaskTable.insert([
                "id": key(subtask.id),
                "task_id": key(task),
                "position": .integer(Int64(position)),
                "title": .text(subtask.title),
                "progress": .text(subtask.progress.stored),
                "execution": .text(subtask.execution.stored),
            ], in: connection)
        }
    }

    static func subtasks(of project: ProjectID, in connection: Connection) throws -> [TaskID: [Subtask]] {
        let rows = try connection.query("""
            SELECT \(subtaskTable.selection) FROM subtasks JOIN tasks ON tasks.id = subtasks.task_id
            WHERE tasks.project_id = ? ORDER BY subtasks.task_id, subtasks.position
            """, [key(project)]) { row -> (TaskID, Subtask)? in
            let record = subtaskTable.record(row)
            guard let task: TaskID = record.id("task_id"), let id: SubtaskID = record.id("id"),
                  let progress = SubtaskProgress(stored: record.text("progress")),
                  let execution = Execution(stored: record.text("execution")) else { return nil }
            return (task, Subtask(id: id, title: record.text("title"), progress: progress, execution: execution))
        }
        return Dictionary(grouping: rows.compactMap(\.self), by: \.0).mapValues { $0.map(\.1) }
    }
}
