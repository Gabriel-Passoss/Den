import Testing
import Foundation
import HarnessCore
import DenStore
@testable import Den

private let harness = HarnessID(rawValue: "test-harness")
private let other = HarnessID(rawValue: "other-harness")

@Test func catalogRoundTripsPerDirectory() {
    withTemporaryCache { cache in
        let directory = URL(fileURLWithPath: "/tmp/den-tests/project")
        let catalog = CommandCatalog(skills: ["review"], supportsCompact: true)
        cache.remember(catalog, for: directory, harness: harness)
        #expect(cache.rememberedCatalog(for: directory, harness: harness) == catalog)
    }
}

@Test func catalogsOfDifferentDirectoriesNeverBleed() {
    withTemporaryCache { cache in
        let one = URL(fileURLWithPath: "/tmp/den-tests/one")
        let two = URL(fileURLWithPath: "/tmp/den-tests/two")
        let first = CommandCatalog(skills: ["review"], supportsCompact: true)
        let second = CommandCatalog(skills: ["deploy"], supportsCompact: false)

        cache.remember(first, for: one, harness: harness)
        cache.remember(second, for: two, harness: harness)

        #expect(cache.rememberedCatalog(for: one, harness: harness) == first)
        #expect(cache.rememberedCatalog(for: two, harness: harness) == second)
    }
}

@Test func catalogFallsBackToTheLastOneForNewDirectories() {
    withTemporaryCache { cache in
        let known = URL(fileURLWithPath: "/tmp/den-tests/known")
        let fresh = URL(fileURLWithPath: "/tmp/den-tests/fresh")
        let catalog = CommandCatalog(skills: ["review"], supportsCompact: true)
        cache.remember(catalog, for: known, harness: harness)
        #expect(cache.rememberedCatalog(for: fresh, harness: harness) == catalog)
        #expect(cache.rememberedCatalog(for: fresh, harness: other) == .empty)
    }
}

@Test func emptyCatalogNeverOverwritesARememberedOne() {
    withTemporaryCache { cache in
        let directory = URL(fileURLWithPath: "/tmp/den-tests/project")
        let catalog = CommandCatalog(skills: ["review"], supportsCompact: true)
        cache.remember(catalog, for: directory, harness: harness)
        cache.remember(.empty, for: directory, harness: harness)
        #expect(cache.rememberedCatalog(for: directory, harness: harness) == catalog)
    }
}

@Test func knobsRoundTripPerHarness() {
    withTemporaryCache { cache in
        let knobs = [HarnessKnob(id: "model", category: .model, name: "Modelo",
                                 currentValue: "opus",
                                 options: [.init(value: "opus", label: "Opus")])]
        cache.remember(knobs, for: harness)
        #expect(cache.rememberedKnobs(for: harness) == knobs)
        #expect(cache.rememberedKnobs(for: other) == [])

        cache.remember([], for: harness)
        #expect(cache.rememberedKnobs(for: harness) == knobs)
    }
}

@Test func preferencesRoundTripPerSession() async throws {
    let repositories = scratchRepositories()
    let cache = SessionCache(repositories)
    let session = storedSession("com preferências")
    try await repositories.sessions.saveMetadata(session)
    #expect(cache.preferences(for: session.id) == [:])

    cache.setPreferences(["theme": "dark"], for: session.id)
    #expect(cache.preferences(for: session.id) == ["theme": "dark"])

    cache.setPreferences([:], for: session.id)
    #expect(cache.preferences(for: session.id) == [:])
}

@Test func preferencesOfASessionTheStoreDoesNotKnowAreDropped() {
    withTemporaryCache { cache in
        let ghost = UUID()
        cache.setPreferences(["theme": "dark"], for: ghost)
        #expect(cache.preferences(for: ghost) == [:])
    }
}

@Test func separateCachesNeverSeeEachOther() {
    let directory = URL(fileURLWithPath: "/tmp/den-tests/project")
    let catalog = CommandCatalog(skills: ["review"], supportsCompact: true)
    withTemporaryCache { first in
        first.remember(catalog, for: directory, harness: harness)
        withTemporaryCache { second in
            #expect(second.rememberedCatalog(for: directory, harness: harness) == .empty)
        }
        #expect(first.rememberedCatalog(for: directory, harness: harness) == catalog)
    }
}
