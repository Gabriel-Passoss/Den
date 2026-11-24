import Testing
import Foundation
import HarnessCore
import DenStore
import SQLiteKit

private struct Note: Codable, Equatable, Sendable {
    var text: String
    var stamp: Date
}

private let precise = Date(timeIntervalSince1970: 1_700_000_000.123456)

private struct Desk {
    let store: Repositories
    let notes: any SessionDocumentRepository<Note>
    let session: UUID

    init() async throws {
        store = try DenStore.inMemory()
        notes = store.documents(kind: "note", as: Note.self)
        session = try await saved(in: store).id
    }
}

@Test func anEmptyStoreHasNoDocuments() throws {
    #expect(try DenStore.inMemory().documents(kind: "note", as: Note.self).all().isEmpty)
}

@Test func aDocumentComesBackExactlyAndCanBeReplaced() async throws {
    let desk = try await Desk()

    try desk.notes.save(Note(text: "primeira", stamp: precise), for: desk.session)
    #expect(desk.notes.all() == [desk.session: Note(text: "primeira", stamp: precise)])

    try desk.notes.save(Note(text: "segunda", stamp: precise), for: desk.session)
    #expect(desk.notes.all() == [desk.session: Note(text: "segunda", stamp: precise)])
}

@Test func kindsNeverMix() async throws {
    let store = try DenStore.inMemory()
    let session = try await saved(in: store).id
    try store.documents(kind: "note", as: Note.self).save(Note(text: "a", stamp: precise), for: session)
    try store.documents(kind: "tag", as: String.self).save("urgente", for: session)

    #expect(store.documents(kind: "note", as: Note.self).all().count == 1)
    #expect(store.documents(kind: "tag", as: String.self).all() == [session: "urgente"])

    try store.documents(kind: "tag", as: String.self).remove(session)
    #expect(store.documents(kind: "tag", as: String.self).all().isEmpty)
    #expect(store.documents(kind: "note", as: Note.self).all().count == 1)
}

@Test func aDocumentForAnUnknownSessionIsRefused() throws {
    let notes = try DenStore.inMemory().documents(kind: "note", as: Note.self)
    let ghost = UUID()

    #expect(throws: SessionRepositoryError.sessionNotFound(ghost)) {
        try notes.save(Note(text: "órfã", stamp: precise), for: ghost)
    }
    try notes.remove(ghost)
    #expect(notes.all().isEmpty)
}

@Test func deletingASessionRemovesItsDocument() async throws {
    let desk = try await Desk()
    try desk.notes.save(Note(text: "some", stamp: precise), for: desk.session)

    try await desk.store.sessions.delete(desk.session)

    #expect(desk.notes.all().isEmpty)
}

@Test func aDocumentThatCannotBeReadIsSkipped() async throws {
    let scratch = try ScratchStore()
    defer { scratch.remove() }
    let store = try scratch.open().repositories
    let notes = store.documents(kind: "note", as: Note.self)
    let good = try await saved(in: store).id
    let bad = try await saved(in: store).id
    try notes.save(Note(text: "boa", stamp: precise), for: good)
    try notes.save(Note(text: "ruim", stamp: precise), for: bad)

    try scratch.raw().write {
        try $0.execute("UPDATE session_documents SET payload = '{nope' WHERE session_id = ?",
                       [.text(bad.uuidString)])
    }

    #expect(notes.all() == [good: Note(text: "boa", stamp: precise)])
}
