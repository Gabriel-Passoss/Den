import Foundation
import HarnessCore

public enum ClaudeSettings {
    public static func permissionMode(
        forWorkingDirectory directory: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> PermissionMode? {
        for file in candidates(directory: directory, home: home) {
            guard let json = object(of: file),
                  let permissions = json["permissions"] as? [String: Any],
                  let raw = permissions["defaultMode"] as? String
            else { continue }
            if raw == "default" { return .manual }
            if let mode = PermissionMode(rawValue: raw) { return mode }
        }
        return nil
    }

    public static func effortLevel(
        forWorkingDirectory directory: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> EffortLevel? {
        for file in candidates(directory: directory, home: home) {
            guard let json = object(of: file),
                  let raw = json["effortLevel"] as? String
            else { continue }
            if let level = EffortLevel(rawValue: raw) { return level }
        }
        return nil
    }

    private static func candidates(directory: URL, home: URL) -> [URL] {
        [
            directory.appendingPathComponent(".claude/settings.local.json"),
            directory.appendingPathComponent(".claude/settings.json"),
            home.appendingPathComponent(".claude/settings.json"),
        ]
    }

    private static func object(of file: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
