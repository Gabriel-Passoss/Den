import Foundation

nonisolated struct ProjectRoot: Hashable, Sendable {
    let url: URL

    init(_ url: URL) {
        self.url = url.standardizedFileURL
    }

    var path: String { url.path }

    static func == (lhs: ProjectRoot, rhs: ProjectRoot) -> Bool {
        lhs.path == rhs.path
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }
}
