import Foundation

nonisolated enum GitRepository {
    static func toplevel(containing directory: URL) -> URL? {
        let manager = FileManager.default
        var probe = directory.standardizedFileURL
        while probe.pathComponents.count > 1 {
            if manager.fileExists(atPath: probe.appending(path: ".git").path) {
                return probe
            }
            probe = probe.deletingLastPathComponent()
        }
        return nil
    }

    static func mainCheckout(of toplevel: URL) -> URL {
        let checkout = toplevel.standardizedFileURL
        let marker = checkout.appending(path: ".git")
        guard !marker.isExistingDirectory,
              let text = try? String(contentsOf: marker, encoding: .utf8),
              let line = text.split(whereSeparator: \.isNewline)
                .first(where: { $0.hasPrefix("gitdir:") }) else { return checkout }
        let gitdir = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        let absolute = gitdir.hasPrefix("/")
            ? URL(fileURLWithPath: gitdir) : checkout.appending(path: gitdir)
        let path = absolute.standardizedFileURL.path
        guard let range = path.range(of: "/.git/worktrees/") else { return checkout }
        return URL(fileURLWithPath: String(path[..<range.lowerBound])).standardizedFileURL
    }
}
