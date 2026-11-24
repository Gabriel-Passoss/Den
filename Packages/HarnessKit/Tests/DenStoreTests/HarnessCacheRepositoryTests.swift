import Testing
import Foundation
import HarnessCore
import DenStore

private let review = CommandCatalog(skills: ["review"], supportsCompact: true)
private let deploy = CommandCatalog(skills: ["deploy"], supportsCompact: false)
private let api = URL(fileURLWithPath: "/tmp/den-tests/api")
private let web = URL(fileURLWithPath: "/tmp/den-tests/web")

@Test func aCatalogIsRememberedPerDirectory() throws {
    let cache = try DenStore.inMemory().harnessCache

    cache.remember(review, for: api, harness: harnessA)
    cache.remember(deploy, for: web, harness: harnessA)

    #expect(cache.catalog(for: api, harness: harnessA) == review)
    #expect(cache.catalog(for: web, harness: harnessA) == deploy)
    #expect(cache.catalog(for: URL(fileURLWithPath: "/tmp/den-tests/web/../api"), harness: harnessA) == review)
}

@Test func aNewDirectoryGetsTheLastCatalogOfItsHarness() throws {
    let cache = try DenStore.inMemory().harnessCache
    #expect(cache.catalog(for: api, harness: harnessA) == .empty)

    cache.remember(review, for: api, harness: harnessA)

    #expect(cache.catalog(for: web, harness: harnessA) == review)
    #expect(cache.catalog(for: web, harness: harnessB) == .empty)
}

@Test func anEmptyCatalogNeverReplacesARememberedOne() throws {
    let cache = try DenStore.inMemory().harnessCache
    cache.remember(review, for: api, harness: harnessA)

    cache.remember(.empty, for: api, harness: harnessA)
    #expect(cache.catalog(for: api, harness: harnessA) == review)

    cache.remember(deploy, for: api, harness: harnessA)
    #expect(cache.catalog(for: api, harness: harnessA) == deploy)
}

@Test func knobsAreRememberedPerHarness() throws {
    let cache = try DenStore.inMemory().harnessCache
    let knobs = [HarnessKnob(id: "model", category: .model, name: "Modelo", currentValue: "opus",
                             options: [.init(value: "opus", label: "Opus")])]

    cache.remember(knobs, for: harnessA)
    cache.remember([], for: harnessA)

    #expect(cache.knobs(for: harnessA) == knobs)
    #expect(cache.knobs(for: harnessB).isEmpty)
}

@Test func directoriesUntouchedForAMonthAreForgottenWhenTheStoreOpens() throws {
    let scratch = try ScratchStore()
    defer { scratch.remove() }
    do {
        let cache = try scratch.open().repositories.harnessCache
        cache.remember(review, for: api, harness: harnessA)
        scratch.clock.advance(by: 20 * 24 * 60 * 60)
        cache.remember(deploy, for: web, harness: harnessA)
    }

    scratch.clock.advance(by: 11 * 24 * 60 * 60)
    let reopened = try scratch.open().repositories.harnessCache

    #expect(reopened.catalog(for: api, harness: harnessA) == deploy)
    #expect(reopened.catalog(for: web, harness: harnessA) == deploy)
}

@Test func aDirectoryUsedWithinTheMonthIsKept() throws {
    let scratch = try ScratchStore()
    defer { scratch.remove() }
    do {
        let cache = try scratch.open().repositories.harnessCache
        cache.remember(review, for: api, harness: harnessA)
        cache.remember(deploy, for: web, harness: harnessA)
    }

    scratch.clock.advance(by: 29 * 24 * 60 * 60)
    let reopened = try scratch.open().repositories.harnessCache

    #expect(reopened.catalog(for: api, harness: harnessA) == review)
}
