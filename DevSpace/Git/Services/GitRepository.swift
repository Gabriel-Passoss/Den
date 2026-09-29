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
}
