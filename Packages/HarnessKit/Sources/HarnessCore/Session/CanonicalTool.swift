public enum CanonicalTool: String, Sendable, Equatable, CaseIterable, Codable {
    case read
    case write
    case edit
    case execute
    case search
    case fetch
}

public struct ToolCall: Sendable, Equatable, Codable {

    public let id: String

    public let rawName: String

    public let canonical: CanonicalTool?
    public let input: JSONValue

    public init(id: String, rawName: String, canonical: CanonicalTool?, input: JSONValue) {
        self.id = id
        self.rawName = rawName
        self.canonical = canonical
        self.input = input
    }

    private enum CodingKeys: String, CodingKey {
        case id, rawName, canonical, input
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        rawName = try container.decode(String.self, forKey: .rawName)
        let rawCanonical = try container.decodeIfPresent(String.self, forKey: .canonical)
        canonical = rawCanonical.flatMap(CanonicalTool.init(rawValue:))
        input = try container.decode(JSONValue.self, forKey: .input)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(rawName, forKey: .rawName)
        try container.encodeIfPresent(canonical?.rawValue, forKey: .canonical)
        try container.encode(input, forKey: .input)
    }
}

public struct ToolResult: Sendable, Equatable, Codable {

    public let callID: String
    public let isError: Bool
    public let content: JSONValue

    public init(callID: String, isError: Bool, content: JSONValue) {
        self.callID = callID
        self.isError = isError
        self.content = content
    }
}
