import Foundation

public struct ProjectIdentity: Hashable, Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = URL(fileURLWithPath: root.resolvingSymlinksInPath().path, isDirectory: true)
    }

    public var name: String { root.lastPathComponent }

    public var slug: String {
        let fingerprint = root.path.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
        return MemorySlug.make(name) + "-" + String(format: "%08x", fingerprint)
    }
}

public enum ProjectLocator {
    public static func project(containing directory: URL) -> ProjectIdentity? {
        var probe = directory.standardizedFileURL
        while true {
            let marker = probe.appending(path: ".git")
            if let isFolder = try? marker.resourceValues(forKeys: [.isDirectoryKey]).isDirectory {
                let origin = isFolder ? nil : origin(ofWorktreeAt: probe, marker: marker)
                return ProjectIdentity(root: origin ?? probe)
            }
            guard probe.pathComponents.count > 1 else { return nil }
            probe = probe.deletingLastPathComponent()
        }
    }

    private static func origin(ofWorktreeAt worktree: URL, marker: URL) -> URL? {
        guard let text = try? String(contentsOf: marker, encoding: .utf8),
              let line = text.split(whereSeparator: \.isNewline).first,
              line.hasPrefix("gitdir:") else { return nil }
        let pointer = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        let administrative = URL(fileURLWithPath: pointer, relativeTo: worktree).standardizedFileURL
        let worktrees = administrative.deletingLastPathComponent()
        let gitDirectory = worktrees.deletingLastPathComponent()
        guard worktrees.lastPathComponent == "worktrees", gitDirectory.lastPathComponent == ".git" else {
            return nil
        }
        return gitDirectory.deletingLastPathComponent()
    }
}
