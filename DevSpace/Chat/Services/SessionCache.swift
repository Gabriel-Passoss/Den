import Foundation
import HarnessCore

nonisolated enum SessionCache {
    private static func catalogKey(_ directory: URL, _ harness: HarnessID) -> String {
        "DevSpace.catalog." + harness.rawValue + "." + directory.standardizedFileURL.path
    }

    private static func lastCatalogKey(_ harness: HarnessID) -> String {
        "DevSpace.catalog.last." + harness.rawValue
    }

    static func remember(_ catalog: CommandCatalog, for directory: URL,
                         harness: HarnessID) {
        guard !catalog.isEmpty,
              let data = try? JSONEncoder().encode(catalog) else { return }
        UserDefaults.standard.set(data, forKey: catalogKey(directory, harness))
        UserDefaults.standard.set(data, forKey: lastCatalogKey(harness))
    }

    static func rememberedCatalog(for directory: URL,
                                  harness: HarnessID) -> CommandCatalog {
        for key in [catalogKey(directory, harness), lastCatalogKey(harness)] {
            if let data = UserDefaults.standard.data(forKey: key),
               let catalog = try? JSONDecoder().decode(CommandCatalog.self, from: data) {
                return catalog
            }
        }
        return .empty
    }

    private static func knobsKey(_ harness: HarnessID) -> String {
        "DevSpace.knobs." + harness.rawValue
    }

    static func remember(_ knobs: [HarnessKnob], for harness: HarnessID) {
        guard !knobs.isEmpty, let data = try? JSONEncoder().encode(knobs) else { return }
        UserDefaults.standard.set(data, forKey: knobsKey(harness))
    }

    static func rememberedKnobs(for harness: HarnessID) -> [HarnessKnob] {
        guard let data = UserDefaults.standard.data(forKey: knobsKey(harness)),
              let knobs = try? JSONDecoder().decode([HarnessKnob].self, from: data)
        else { return [] }
        return knobs
    }

    private static let preferencesKey = "DevSpace.sessionPreferences"

    static func preferences(for sessionID: UUID) -> [String: String] {
        let all = UserDefaults.standard.dictionary(forKey: preferencesKey)
            as? [String: [String: String]] ?? [:]
        return all[sessionID.uuidString] ?? [:]
    }

    static func setPreferences(_ values: [String: String], for sessionID: UUID) {
        var all = UserDefaults.standard.dictionary(forKey: preferencesKey)
            as? [String: [String: String]] ?? [:]
        all[sessionID.uuidString] = values.isEmpty ? nil : values
        UserDefaults.standard.set(all, forKey: preferencesKey)
    }
}
