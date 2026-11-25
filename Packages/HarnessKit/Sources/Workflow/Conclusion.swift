public enum Conclusion: Sendable, Equatable {
    case undecided
    case returnToUser(Passage?)
    case move(to: StageID, passage: Passage?)
}

public enum ConclusionOutcome: Sendable, Equatable {
    case moved
    case waitingForUser
    case refused(MoveRefusal)
    case chainLimitReached
}

public struct ChainLimit: Sendable, Equatable {
    public static let standard = ChainLimit(moves: 5)

    public let moves: Int

    public init(moves: Int) {
        self.moves = max(1, moves)
    }
}
