import Foundation

public enum Author: Sendable, Equatable {
    case user
    case agent(AgentID)
}

public struct Movement: Sendable, Equatable {
    public let from: StageID
    public let to: StageID
    public let author: Author
    public let at: Date
    public internal(set) var passage: Passage?

    public init(from: StageID, to: StageID, author: Author, at: Date, passage: Passage? = nil) {
        self.from = from
        self.to = to
        self.author = author
        self.at = at
        self.passage = passage
    }
}
