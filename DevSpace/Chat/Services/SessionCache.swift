import Foundation
import HarnessCore

nonisolated struct SessionCache {
    let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    static let standard = SessionCache(defaults: .standard)

    private func catalogKey(_ directory: URL, _ harness: HarnessID) -> String {
        "DevSpace.catalog." + harness.rawValue + "." + directory.standardizedFileURL.path
    }

    private func lastCatalogKey(_ harness: HarnessID) -> String {
        "DevSpace.catalog.last." + harness.rawValue
    }

    func remember(_ catalog: CommandCatalog, for directory: URL,
                  harness: HarnessID) {
        guard !catalog.isEmpty,
              let data = try? JSONEncoder().encode(catalog) else { return }
        defaults.set(data, forKey: catalogKey(directory, harness))
        defaults.set(data, forKey: lastCatalogKey(harness))
    }

    func rememberedCatalog(for directory: URL,
                           harness: HarnessID) -> CommandCatalog {
        for key in [catalogKey(directory, harness), lastCatalogKey(harness)] {
            if let data = defaults.data(forKey: key),
               let catalog = try? JSONDecoder().decode(CommandCatalog.self, from: data) {
                return catalog
            }
        }
        return .empty
    }

    private func knobsKey(_ harness: HarnessID) -> String {
        "DevSpace.knobs." + harness.rawValue
    }

    func remember(_ knobs: [HarnessKnob], for harness: HarnessID) {
        guard !knobs.isEmpty, let data = try? JSONEncoder().encode(knobs) else { return }
        defaults.set(data, forKey: knobsKey(harness))
    }

    func rememberedKnobs(for harness: HarnessID) -> [HarnessKnob] {
        guard let data = defaults.data(forKey: knobsKey(harness)),
              let knobs = try? JSONDecoder().decode([HarnessKnob].self, from: data)
        else { return [] }
        return knobs
    }

    private let preferencesKey = "DevSpace.sessionPreferences"

    func preferences(for sessionID: UUID) -> [String: String] {
        let all = defaults.dictionary(forKey: preferencesKey)
            as? [String: [String: String]] ?? [:]
        return all[sessionID.uuidString] ?? [:]
    }

    func setPreferences(_ values: [String: String], for sessionID: UUID) {
        var all = defaults.dictionary(forKey: preferencesKey)
            as? [String: [String: String]] ?? [:]
        all[sessionID.uuidString] = values.isEmpty ? nil : values
        defaults.set(all, forKey: preferencesKey)
    }
}
