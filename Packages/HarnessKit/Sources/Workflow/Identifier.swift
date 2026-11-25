import Foundation

// periphery:ignore
public struct Identifier<Subject>: Hashable, Sendable, Codable {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public typealias StageID = Identifier<Stage>
public typealias TaskID = Identifier<BoardTask>
public typealias SubtaskID = Identifier<Subtask>
public typealias PendencyID = Identifier<Pendency>

public struct AgentID: Hashable, Sendable, Codable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}
