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
