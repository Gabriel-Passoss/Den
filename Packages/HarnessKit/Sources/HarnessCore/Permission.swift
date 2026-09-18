public struct PermissionRequest: Equatable, Sendable, Codable {
    public let id: String
    public let toolName: String
    public let displayName: String?
    public let description: String?
    public let input: JSONValue
    public let toolUseID: String?

    public let suggestions: [PermissionSuggestion]

    public init(
        id: String,
        toolName: String,
        displayName: String? = nil,
        description: String? = nil,
        input: JSONValue = .null,
        toolUseID: String? = nil,
        suggestions: [PermissionSuggestion] = []
    ) {
        self.id = id
        self.toolName = toolName
        self.displayName = displayName
        self.description = description
        self.input = input
        self.toolUseID = toolUseID
        self.suggestions = suggestions
    }
}

public struct PermissionSuggestion: Equatable, Sendable, Codable {
    public let type: String?
    public let mode: String?
    public let destination: String?
    public let behavior: String?

    public let raw: JSONValue

    public init(
        type: String? = nil,
        mode: String? = nil,
        destination: String? = nil,
        behavior: String? = nil,
        raw: JSONValue = .null
    ) {
        self.type = type
        self.mode = mode
        self.destination = destination
        self.behavior = behavior
        self.raw = raw
    }
}

public enum PermissionDecision: Equatable, Sendable, Codable {
    case allow(updatedInput: JSONValue?)
    case deny(message: String, interrupt: Bool)
}

public enum PermissionMode: String, Equatable, Sendable, CaseIterable {
    case acceptEdits
    case auto
    case bypassPermissions
    case manual
    case dontAsk
    case plan
}
