import Testing
import Foundation
import HarnessCore
import DenStore

@Test func aSessionWithoutPreferencesHasNone() async throws {
    let store = try DenStore.inMemory()
    let session = try await saved(in: store).id

    #expect(store.preferences.preferences(for: session).isEmpty)
    #expect(store.preferences.preferences(for: UUID()).isEmpty)
}

@Test func preferencesAreReplacedAsAWhole() async throws {
    let store = try DenStore.inMemory()
    let session = try await saved(in: store).id
    let other = try await saved(in: store).id

    try store.preferences.setPreferences(["model": "opus", "effort": "high"], for: session)
    try store.preferences.setPreferences(["model": "haiku"], for: other)
    #expect(store.preferences.preferences(for: session) == ["model": "opus", "effort": "high"])

    try store.preferences.setPreferences(["model": "sonnet"], for: session)
    #expect(store.preferences.preferences(for: session) == ["model": "sonnet"])
    #expect(store.preferences.preferences(for: other) == ["model": "haiku"])

    try store.preferences.setPreferences([:], for: session)
    #expect(store.preferences.preferences(for: session).isEmpty)
}

@Test func preferencesForAnUnknownSessionAreRefused() throws {
    let store = try DenStore.inMemory()
    let ghost = UUID()

    #expect(throws: SessionRepositoryError.sessionNotFound(ghost)) {
        try store.preferences.setPreferences(["model": "opus"], for: ghost)
    }
    #expect(store.preferences.preferences(for: ghost).isEmpty)
}

@Test func deletingASessionForgetsItsPreferences() async throws {
    let store = try DenStore.inMemory()
    let session = try await saved(in: store)
    try store.preferences.setPreferences(["model": "opus"], for: session.id)

    try await store.sessions.delete(session.id)
    try await store.sessions.saveMetadata(session)

    #expect(store.preferences.preferences(for: session.id).isEmpty)
}
