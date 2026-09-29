import Foundation

nonisolated enum RunProjectLocator {
    static func root(for directory: URL, knownRoots: Set<ProjectRoot>) -> URL {
        let start = directory.standardizedFileURL
        var probe = start
        while true {
            if knownRoots.contains(ProjectRoot(probe)) { return probe }
            guard probe.pathComponents.count > 1 else { break }
            probe = probe.deletingLastPathComponent()
        }
        return GitRepository.toplevel(containing: start) ?? start
    }
}
