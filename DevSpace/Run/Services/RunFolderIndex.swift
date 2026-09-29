import Foundation

nonisolated struct RunFolder: Equatable, Identifiable, Sendable {
    let path: String
    let marker: String?

    var id: String { path }
}

nonisolated enum RunFolderIndex {
    static let markers = [
        "package.json", "Makefile", "Cargo.toml", "Package.swift", "go.mod",
        "pyproject.toml", "Gemfile", "compose.yaml", "docker-compose.yml",
    ]

    static func folders(under root: URL, maxDepth: Int = 4, limit: Int = 2_000) -> [RunFolder] {
        var result: [RunFolder] = []

        func visit(_ directory: URL, prefix: String, depth: Int) {
            guard depth <= maxDepth, result.count < limit,
                  let children = try? FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]) else { return }
            let sorted = children.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
            for child in sorted {
                guard result.count < limit else { return }
                let name = child.lastPathComponent
                guard (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                      !ProjectScan.skippedFolders.contains(name) else { continue }
                let path = prefix.isEmpty ? name : prefix + "/" + name
                result.append(RunFolder(path: path, marker: marker(in: child)))
                visit(child, prefix: path, depth: depth + 1)
            }
        }

        visit(root, prefix: "", depth: 1)
        return result
    }

    static func marker(in directory: URL) -> String? {
        markers.first { FileManager.default.fileExists(atPath: directory.appending(path: $0).path) }
    }

    static func filter(_ folders: [RunFolder], query: String) -> [RunFolder] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return folders }
        return folders.filter { $0.path.localizedCaseInsensitiveContains(trimmed) }
    }

    static func pinnedSelection(_ selection: String, in folders: [RunFolder]) -> String? {
        guard !selection.isEmpty, !folders.contains(where: { $0.path == selection }) else { return nil }
        return selection
    }
}
