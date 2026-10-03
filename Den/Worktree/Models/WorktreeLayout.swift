import Foundation

nonisolated struct RepoCandidate: Equatable, Hashable, Sendable, Identifiable {
    let toplevel: URL
    let main: URL

    var id: String { toplevel.path }
    var name: String { main.lastPathComponent }

    init(toplevel: URL, main: URL) {
        self.toplevel = URL(filePath: toplevel.standardizedFileURL.path, directoryHint: .notDirectory)
        self.main = URL(filePath: main.standardizedFileURL.path, directoryHint: .notDirectory)
    }

    init(toplevel: URL) {
        self.init(toplevel: toplevel, main: GitRepository.mainCheckout(of: toplevel))
    }
}

nonisolated enum WorktreeLayout: Equatable, Sendable {
    case single(RepoCandidate)
    case multiple(folder: URL, repos: [RepoCandidate])

    var repos: [RepoCandidate] {
        switch self {
        case .single(let repo): [repo]
        case .multiple(_, let repos): repos
        }
    }

    static func detect(_ directory: URL) -> WorktreeLayout? {
        if let toplevel = GitRepository.toplevel(containing: directory) {
            return .single(RepoCandidate(toplevel: toplevel))
        }
        let repos = GitChangesModel.discoverRepoRoots(under: directory)
            .map { RepoCandidate(toplevel: $0) }
        let folder = URL(filePath: directory.standardizedFileURL.path, directoryHint: .notDirectory)
        return repos.isEmpty ? nil : .multiple(folder: folder, repos: repos)
    }
}
