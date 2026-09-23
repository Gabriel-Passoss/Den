import Foundation
import HarnessCore

nonisolated enum SessionCache {
    /// O catálogo é de um harness, não da pasta: guardar os dois juntos faria
    /// o menu do OpenCode abrir com as skills do Claude.
    private static func catalogKey(_ directory: URL, _ harness: HarnessID) -> String {
        "DevSpace.catalog." + harness.rawValue + "." + directory.standardizedFileURL.path
    }

    /// O catálogo só chega quando a sessão sobe; guardar por pasta deixa o
    /// menu de comandos pronto já na primeira digitada de uma sessão fria.
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

    /// Pasta ainda sem catálogo cai no último conhecido: skills e MCP são
    /// quase sempre do usuário, e o catálogo real chega no primeiro turno.
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

    /// Modelo e modo do OpenCode só existem depois do handshake, então numa
    /// sessão ainda fria a barra ficaria vazia. O último conjunto conhecido
    /// segura o lugar até a sessão subir e dizer o que vale agora.
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
