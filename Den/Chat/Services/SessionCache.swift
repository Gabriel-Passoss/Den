import Foundation
import HarnessCore
import DenStore

nonisolated struct SessionCache {
    private let sessionPreferences: any SessionPreferencesRepository
    private let harnessCache: any HarnessCacheRepository

    init(_ repositories: Repositories) {
        sessionPreferences = repositories.preferences
        harnessCache = repositories.harnessCache
    }

    func remember(_ catalog: CommandCatalog, for directory: URL, harness: HarnessID) {
        harnessCache.remember(catalog, for: directory, harness: harness)
    }

    func rememberedCatalog(for directory: URL, harness: HarnessID) -> CommandCatalog {
        harnessCache.catalog(for: directory, harness: harness)
    }

    func remember(_ knobs: [HarnessKnob], for harness: HarnessID) {
        harnessCache.remember(knobs, for: harness)
    }

    func rememberedKnobs(for harness: HarnessID) -> [HarnessKnob] {
        harnessCache.knobs(for: harness)
    }

    func preferences(for sessionID: UUID) -> [String: String] {
        sessionPreferences.preferences(for: sessionID)
    }

    func setPreferences(_ values: [String: String], for sessionID: UUID) {
        do {
            try sessionPreferences.setPreferences(values, for: sessionID)
        } catch {
            print("não consegui gravar as preferências da sessão: \(error)")
        }
    }
}
