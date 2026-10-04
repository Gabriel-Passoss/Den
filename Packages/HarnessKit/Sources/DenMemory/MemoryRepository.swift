import Foundation

public enum MemoryScope: Hashable, Sendable {
    case user
    case project(ProjectIdentity)

    public var layer: MemoryLayer {
        switch self {
        case .user: .user
        case .project: .project
        }
    }

    public var heading: String {
        switch self {
        case .user: "Memória do usuário"
        case .project(let project): "Memória do projeto \(project.name)"
        }
    }
}

public enum MemoryRepositoryError: Error, Equatable {
    case unsafeName(String)
}

public protocol MemoryRepository: Sendable {
    func pages(in scope: MemoryScope) -> [MemoryPage]

    func save(_ page: MemoryPage, in scope: MemoryScope) throws

    func delete(_ slug: String, in scope: MemoryScope) throws

    func file(for slug: String, in scope: MemoryScope) -> URL

    func directory(of scope: MemoryScope) -> URL
}

extension MemoryPage {
    var listKey: (Int, String, String) {
        (MemoryCategory.allCases.firstIndex(of: category) ?? 0, title.lowercased(), slug)
    }
}
