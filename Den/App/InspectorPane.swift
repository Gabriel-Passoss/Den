import Foundation

enum InspectorPane: String {
    case closed = ""
    case changes
    case run

    static let storageKey = "Den.inspector"
    private static let legacyKey = "Den.gitInspector"

    static func migrateLegacy(in defaults: UserDefaults) {
        guard defaults.object(forKey: legacyKey) != nil else { return }
        if defaults.bool(forKey: legacyKey), defaults.string(forKey: storageKey) == nil {
            defaults.set(InspectorPane.changes.rawValue, forKey: storageKey)
        }
        defaults.removeObject(forKey: legacyKey)
    }
}
