public enum PermissionDecision: Equatable, Sendable, Codable {
    case allow(updatedInput: JSONValue?)
    case deny(message: String, interrupt: Bool)

    case option(id: String)
}
