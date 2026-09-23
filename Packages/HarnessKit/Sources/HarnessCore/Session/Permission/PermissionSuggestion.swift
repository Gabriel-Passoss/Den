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
