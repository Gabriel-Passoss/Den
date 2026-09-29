import Foundation

enum LegacyDevSpace {
    static let bundleIdentifier = "gabrielpassos.DevSpace"
    static let folderName = "DevSpace"
    private static let keyPrefix = "DevSpace."
    private static let renamedPrefix = "Den."

    static func migrate(into support: URL, defaults: UserDefaults) {
        let legacy = support.deletingLastPathComponent().appending(path: folderName)
        moveFolder(from: legacy, to: support)
        importPreferences(defaults.persistentDomain(forName: bundleIdentifier) ?? [:], into: defaults)
    }

    static func moveFolder(from legacy: URL, to support: URL) {
        let files = FileManager.default
        let kind = (try? files.attributesOfItem(atPath: legacy.path))?[.type] as? FileAttributeType
        guard kind == .typeDirectory, !files.fileExists(atPath: support.path)
        else { return }
        guard (try? files.moveItem(at: legacy, to: support)) != nil else { return }
        try? files.createSymbolicLink(at: legacy, withDestinationURL: support)
    }

    static let importedKey = "Den.importedDevSpacePreferences"

    static func importPreferences(_ legacy: [String: Any], into defaults: UserDefaults) {
        guard !defaults.bool(forKey: importedKey) else { return }
        defaults.set(true, forKey: importedKey)
        for (key, value) in legacy where key.hasPrefix(keyPrefix) {
            let renamed = renamedPrefix + key.dropFirst(keyPrefix.count)
            if defaults.object(forKey: renamed) == nil {
                defaults.set(value, forKey: renamed)
            }
        }
    }
}
