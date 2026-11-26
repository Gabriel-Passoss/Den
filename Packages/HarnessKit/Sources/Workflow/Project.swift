import Foundation

public struct Project: Sendable, Equatable, Identifiable {
    public let id: ProjectID
    public let name: String
    public let root: URL

    public init(id: ProjectID = ProjectID(), name: String, root: URL) {
        self.id = id
        self.name = name
        self.root = root
    }
}
