import Testing
import Foundation
import HarnessCore
@testable import DevSpace

private func uniqueHarness() -> HarnessID {
    HarnessID(rawValue: "test-" + UUID().uuidString)
}

private func forget(_ directories: [URL], _ harness: HarnessID) {
    let defaults = UserDefaults.standard
    for directory in directories {
        defaults.removeObject(forKey: "DevSpace.catalog." + harness.rawValue + "."
                              + directory.standardizedFileURL.path)
    }
    defaults.removeObject(forKey: "DevSpace.catalog.last." + harness.rawValue)
    defaults.removeObject(forKey: "DevSpace.knobs." + harness.rawValue)
}

@Test func catalogRoundTripsPerDirectory() {
    let harness = uniqueHarness()
    let directory = URL(fileURLWithPath: "/tmp/devspace-tests/projeto")
    defer { forget([directory], harness) }

    let catalog = CommandCatalog(skills: ["review"], supportsCompact: true)
    SessionCache.remember(catalog, for: directory, harness: harness)
    #expect(SessionCache.rememberedCatalog(for: directory, harness: harness) == catalog)
}

@Test func catalogFallsBackToTheLastOneForNewDirectories() {
    let harness = uniqueHarness()
    let known = URL(fileURLWithPath: "/tmp/devspace-tests/conhecido")
    let fresh = URL(fileURLWithPath: "/tmp/devspace-tests/novo")
    defer { forget([known, fresh], harness) }

    let catalog = CommandCatalog(skills: ["review"], supportsCompact: true)
    SessionCache.remember(catalog, for: known, harness: harness)
    #expect(SessionCache.rememberedCatalog(for: fresh, harness: harness) == catalog)
    #expect(SessionCache.rememberedCatalog(for: fresh, harness: uniqueHarness()) == .empty)
}

@Test func emptyCatalogNeverOverwritesARememberedOne() {
    let harness = uniqueHarness()
    let directory = URL(fileURLWithPath: "/tmp/devspace-tests/projeto")
    defer { forget([directory], harness) }

    let catalog = CommandCatalog(skills: ["review"], supportsCompact: true)
    SessionCache.remember(catalog, for: directory, harness: harness)
    SessionCache.remember(.empty, for: directory, harness: harness)
    #expect(SessionCache.rememberedCatalog(for: directory, harness: harness) == catalog)
}

@Test func knobsRoundTripPerHarness() {
    let harness = uniqueHarness()
    defer { forget([], harness) }

    let knobs = [HarnessKnob(id: "model", category: .model, name: "Modelo",
                             currentValue: "opus",
                             options: [.init(value: "opus", label: "Opus")])]
    SessionCache.remember(knobs, for: harness)
    #expect(SessionCache.rememberedKnobs(for: harness) == knobs)
    #expect(SessionCache.rememberedKnobs(for: uniqueHarness()) == [])

    SessionCache.remember([], for: harness)
    #expect(SessionCache.rememberedKnobs(for: harness) == knobs)
}

@Test func preferencesRoundTripPerSession() {
    let session = UUID()
    #expect(SessionCache.preferences(for: session) == [:])

    SessionCache.setPreferences(["tema": "escuro"], for: session)
    #expect(SessionCache.preferences(for: session) == ["tema": "escuro"])

    SessionCache.setPreferences([:], for: session)
    #expect(SessionCache.preferences(for: session) == [:])
}
