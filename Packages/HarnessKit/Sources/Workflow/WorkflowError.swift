public enum WorkflowError: Error, Sendable, Equatable {
    case blankName
    case unknownStage
    case unknownTask
    case unknownSubtask
    case unknownPendency
    case stageHasTasks
    case boardHasNoStages
    case alreadyInStage
    case stageHasNoAgent
    case executionNotRunning
    case executionAlreadyRunning
    case notADecision
    case noPassageAwaited
}
