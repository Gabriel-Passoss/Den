import Foundation

public enum ClaudeSettings {
    public static func effortLevel(
        forWorkingDirectory directory: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> EffortLevel? {
        let candidates = [
            directory.appendingPathComponent(".claude/settings.local.json"),
            directory.appendingPathComponent(".claude/settings.json"),
            home.appendingPathComponent(".claude/settings.json"),
        ]
        for file in candidates {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let raw = json["effortLevel"] as? String
            else { continue }
            if let level = EffortLevel(rawValue: raw) { return level }
        }
        return nil
    }
}
