public extension Board {
    @discardableResult
    mutating func addSubtask(titled title: String, to id: TaskID) throws -> SubtaskID {
        let title = try Self.validName(title)
        let index = try runningTaskIndex(id)
        let subtask = Subtask(title: title)
        tasks[index].subtasks.append(subtask)
        return subtask.id
    }

    mutating func setProgress(_ progress: SubtaskProgress, of id: SubtaskID) throws {
        let (task, position) = try subtaskPosition(id, parentRunning: true)
        tasks[task].subtasks[position].progress = progress
    }

    mutating func startSubagent(for id: SubtaskID) throws {
        let (task, position) = try subtaskPosition(id, parentRunning: true)
        guard tasks[task].subtasks[position].execution != .running else { throw WorkflowError.executionAlreadyRunning }
        tasks[task].subtasks[position].execution = .running
    }

    mutating func endSubagent(for id: SubtaskID) throws {
        let (task, position) = try subtaskPosition(id, parentRunning: false)
        guard tasks[task].subtasks[position].execution == .running else { throw WorkflowError.executionNotRunning }
        tasks[task].subtasks[position].execution = .finished
    }

    private func subtaskPosition(_ id: SubtaskID, parentRunning: Bool) throws -> (task: Int, position: Int) {
        for (task, candidate) in tasks.enumerated() {
            guard let position = candidate.subtasks.firstIndex(where: { $0.id == id }) else { continue }
            if parentRunning, candidate.execution != .running { throw WorkflowError.executionNotRunning }
            return (task, position)
        }
        throw WorkflowError.unknownSubtask
    }
}
