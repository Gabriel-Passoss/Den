import Foundation

nonisolated struct GitHubRemote: Codable, Equatable, Hashable, Sendable {
    let host: String
    let owner: String
    let name: String

    init(host: String, owner: String, name: String) {
        self.host = host
        self.owner = owner
        self.name = name
    }

    init?(remoteURL: String) {
        let text = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var host: String?
        var path: String?
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(),
           ["https", "http", "ssh", "git"].contains(scheme), let found = url.host() {
            host = found
            path = url.path()
        } else if let match = text.wholeMatch(of: #/(?:[^@/]+@)?([^:/]+):([^/].*)/#) {
            host = String(match.1)
            path = String(match.2)
        }
        guard let host, let path else { return nil }
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 2 else { return nil }
        var repo = parts[1]
        if repo.hasSuffix(".git") { repo.removeLast(4) }
        guard !parts[0].isEmpty, !repo.isEmpty else { return nil }
        self.init(host: host.lowercased(), owner: parts[0], name: repo)
    }
}
