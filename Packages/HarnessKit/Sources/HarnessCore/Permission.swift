public struct PermissionOption: Equatable, Sendable, Codable {

    public enum Kind: String, Equatable, Sendable, Codable {
        case allowOnce, allowAlways, rejectOnce, rejectAlways

        case other
    }

    public let id: String
    public let kind: Kind
    public let label: String

    public init(id: String, kind: Kind, label: String) {
        self.id = id
        self.kind = kind
        self.label = label
    }

    public var isAllow: Bool { kind == .allowOnce || kind == .allowAlways }

    private enum CodingKeys: String, CodingKey { case id, kind, label }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)

        let raw = try container.decode(String.self, forKey: .kind)
        kind = Kind(rawValue: raw) ?? .other
    }
}

public struct PermissionRequest: Equatable, Sendable, Codable {
    public let id: String
    public let toolName: String
    public let displayName: String?
    public let description: String?
    public let input: JSONValue
    public let toolUseID: String?

    public let suggestions: [PermissionSuggestion]

    public let options: [PermissionOption]

    public init(
        id: String,
        toolName: String,
        displayName: String? = nil,
        description: String? = nil,
        input: JSONValue = .null,
        toolUseID: String? = nil,
        suggestions: [PermissionSuggestion] = [],
        options: [PermissionOption] = []
    ) {
        self.id = id
        self.toolName = toolName
        self.displayName = displayName
        self.description = description
        self.input = input
        self.toolUseID = toolUseID
        self.suggestions = suggestions
        self.options = options
    }

    private enum CodingKeys: String, CodingKey {
        case id, toolName, displayName, description, input, toolUseID
        case suggestions, options
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        toolName = try container.decode(String.self, forKey: .toolName)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        input = try container.decodeIfPresent(JSONValue.self, forKey: .input) ?? .null
        toolUseID = try container.decodeIfPresent(String.self, forKey: .toolUseID)

        suggestions = try container.decodeIfPresent(
            [PermissionSuggestion].self, forKey: .suggestions) ?? []
        options = try container.decodeIfPresent(
            [PermissionOption].self, forKey: .options) ?? []
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

    case option(id: String)
}

public enum PermissionMode: String, Equatable, Sendable, CaseIterable {
    case acceptEdits
    case auto
    case bypassPermissions
    case manual
    case dontAsk
    case plan
}
