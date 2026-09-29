import Foundation

nonisolated struct RunConfiguration: Codable, Identifiable, Equatable, Sendable {
    nonisolated enum Kind: Equatable, Sendable {
        case command(CommandSpec)
        case compound([UUID])
    }

    let id: UUID
    var name: String
    var kind: Kind

    init(id: UUID = UUID(), name: String, kind: Kind) {
        self.id = id
        self.name = name
        self.kind = kind
    }

    var command: CommandSpec? {
        if case .command(let spec) = kind { return spec }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, type, command, members
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        switch try container.decode(String.self, forKey: .type) {
        case "command":
            kind = .command(try container.decode(CommandSpec.self, forKey: .command))
        case "compound":
            kind = .compound(try container.decode([UUID].self, forKey: .members))
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "unknown configuration type \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        switch kind {
        case .command(let spec):
            try container.encode("command", forKey: .type)
            try container.encode(spec, forKey: .command)
        case .compound(let members):
            try container.encode("compound", forKey: .type)
            try container.encode(members, forKey: .members)
        }
    }
}

nonisolated struct CommandSpec: Codable, Equatable, Sendable {
    var command: String
    var workingDirectory: String
    var environment: [EnvVar]

    func resolvedDirectory(in root: URL) -> URL {
        Self.directory(workingDirectory, in: root)
    }

    static func directory(_ path: String, in root: URL) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return root }
        if trimmed.hasPrefix("/") { return URL(fileURLWithPath: trimmed) }
        return root.appending(path: trimmed)
    }
}

nonisolated struct EnvVar: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var key: String
    var value: String

    init(id: UUID = UUID(), key: String, value: String) {
        self.id = id
        self.key = key
        self.value = value
    }
}
