import Foundation

public protocol WorkflowIdentifier: Hashable, Sendable, Codable {
    var rawValue: UUID { get }
    init(rawValue: UUID)
}

public extension WorkflowIdentifier {
    init() {
        self.init(rawValue: UUID())
    }
}

public struct ProjectID: WorkflowIdentifier { public let rawValue: UUID; public init(rawValue: UUID) { self.rawValue = rawValue } }

public struct StageID: WorkflowIdentifier { public let rawValue: UUID; public init(rawValue: UUID) { self.rawValue = rawValue } }

public struct TaskID: WorkflowIdentifier { public let rawValue: UUID; public init(rawValue: UUID) { self.rawValue = rawValue } }

public struct SubtaskID: WorkflowIdentifier { public let rawValue: UUID; public init(rawValue: UUID) { self.rawValue = rawValue } }

public struct PendencyID: WorkflowIdentifier { public let rawValue: UUID; public init(rawValue: UUID) { self.rawValue = rawValue } }

public struct AgentID: Hashable, Sendable, Codable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}
