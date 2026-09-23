import Foundation

public struct CommandCatalog: Sendable, Equatable, Codable {
    public enum ServerStatus: String, Sendable, Equatable, Codable {
        case connected, needsAuth = "needs-auth", failed, pending
    }

    public struct Server: Sendable, Equatable, Identifiable, Codable {
        public let name: String
        public let status: ServerStatus
        public let prompts: [String]

        public var id: String { name }

        public init(name: String, status: ServerStatus, prompts: [String] = []) {
            self.name = name
            self.status = status
            self.prompts = prompts
        }
    }

    public var skills: [String]
    public var servers: [Server]
    public var supportsCompact: Bool

    public init(skills: [String] = [], servers: [Server] = [],
                supportsCompact: Bool = false) {
        self.skills = skills
        self.servers = servers
        self.supportsCompact = supportsCompact
    }

    public static let empty = CommandCatalog()

    public static let compactCommand = "/compact"

    public var isEmpty: Bool {
        skills.isEmpty && servers.isEmpty && !supportsCompact
    }
}
