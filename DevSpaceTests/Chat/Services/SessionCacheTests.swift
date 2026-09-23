import Testing
import Foundation
import HarnessCore
@testable import DevSpace

private let harness = HarnessID(rawValue: "test-harness")
private let outro = HarnessID(rawValue: "outro-harness")

@Test func catalogRoundTripsPerDirectory() {
    withTemporaryCache { cache in
        let directory = URL(fileURLWithPath: "/tmp/devspace-tests/projeto")
        let catalog = CommandCatalog(skills: ["review"], supportsCompact: true)
        cache.remember(catalog, for: directory, harness: harness)
        #expect(cache.rememberedCatalog(for: directory, harness: harness) == catalog)
    }
}

@Test func catalogFallsBackToTheLastOneForNewDirectories() {
    withTemporaryCache { cache in
        let known = URL(fileURLWithPath: "/tmp/devspace-tests/conhecido")
        let fresh = URL(fileURLWithPath: "/tmp/devspace-tests/novo")
        let catalog = CommandCatalog(skills: ["review"], supportsCompact: true)
        cache.remember(catalog, for: known, harness: harness)
        #expect(cache.rememberedCatalog(for: fresh, harness: harness) == catalog)
        #expect(cache.rememberedCatalog(for: fresh, harness: outro) == .empty)
    }
}

@Test func emptyCatalogNeverOverwritesARememberedOne() {
    withTemporaryCache { cache in
        let directory = URL(fileURLWithPath: "/tmp/devspace-tests/projeto")
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
        #expect(cache.rememberedKnobs(for: outro) == [])

        cache.remember([], for: harness)
        #expect(cache.rememberedKnobs(for: harness) == knobs)
    }
}

@Test func preferencesRoundTripPerSession() {
    withTemporaryCache { cache in
        let session = UUID()
        #expect(cache.preferences(for: session) == [:])

        cache.setPreferences(["tema": "escuro"], for: session)
        #expect(cache.preferences(for: session) == ["tema": "escuro"])

        cache.setPreferences([:], for: session)
        #expect(cache.preferences(for: session) == [:])
    }
}

@Test func separateCachesNeverSeeEachOther() {
    let directory = URL(fileURLWithPath: "/tmp/devspace-tests/projeto")
    let catalog = CommandCatalog(skills: ["review"], supportsCompact: true)
    withTemporaryCache { first in
        first.remember(catalog, for: directory, harness: harness)
        withTemporaryCache { second in
            #expect(second.rememberedCatalog(for: directory, harness: harness) == .empty)
        }
        #expect(first.rememberedCatalog(for: directory, harness: harness) == catalog)
    }
}
