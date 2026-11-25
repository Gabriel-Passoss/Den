public enum Decision: Sendable, Equatable {
    case permission
    case question
}

public enum MoveRefusal: Sendable, Equatable {
    case unknownStage
    case sameStage
    case missingPassage
    case openSubtasks
}

public enum Problem: Sendable, Equatable {
    case moveRefused(MoveRefusal)
    case passageFailed
    case subagentFailed(SubtaskID)
    case executionFailed(String)
    case interrupted
}

public struct Pendency: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case decision(Decision)
        case stageFinished
        case returned(Passage)
        case chainLimitReached(destination: StageID, passage: Passage)
        case problem(Problem)
    }

    public let id: PendencyID
    public let kind: Kind

    public init(id: PendencyID = PendencyID(), kind: Kind) {
        self.id = id
        self.kind = kind
    }

    var waitsForTheNextTurn: Bool {
        switch kind {
        case .stageFinished, .returned, .chainLimitReached: true
        case .decision, .problem: false
        }
    }

    var isDecision: Bool {
        if case .decision = kind { return true }
        return false
    }
}
