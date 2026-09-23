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
