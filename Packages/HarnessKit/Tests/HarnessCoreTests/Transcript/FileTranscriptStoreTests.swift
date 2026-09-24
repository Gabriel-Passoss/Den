import Testing
import Foundation
@testable import HarnessCore
import HarnessTestSupport

private let harnessA = HarnessID(rawValue: "harness-a")
private let harnessB = HarnessID(rawValue: "harness-b")

private let when = Date(timeIntervalSince1970: 1_700_000_000)

private func makeRoot() throws -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("transcript-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func entry(_ text: String) -> TranscriptEntry {
    TranscriptEntry(timestamp: when, kind: .assistantText(text), raw: .object(["t": .string(text)]))
}

private func newSession(segments: [Segment]) -> Session {
    Session(title: "uma conversa", workingDirectory: URL(fileURLWithPath: "/tmp/repo"),
            segments: segments)
}

private func newSegment(_ harness: HarnessID = harnessA) -> Segment {
    Segment(harness: harness, harnessSessionID: UUID().uuidString, model: "m")
}

@Test func aSessionRoundTripsThroughDisk() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let segment = newSegment()
    let session = newSession(segments: [segment])
    let first = entry("one")
    let second = entry("two")
    try await store.saveMetadata(session)
    try await store.append(first, to: segment.id, in: session.id)
    try await store.append(second, to: segment.id, in: session.id)

    var expected = session
    expected.segments[0].entries = [first, second]

    let loaded = try await store.load(session.id)
    #expect(loaded == expected)
}

@Test func theRawPayloadSurvivesDisk() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)
    let segment = newSegment()
    let session = newSession(segments: [segment])
    try await store.saveMetadata(session)
    try await store.append(entry("x"), to: segment.id, in: session.id)

    let loaded = try await store.load(session.id)
    #expect(loaded.allEntries.first?.raw["t"] == .string("x"))
}

@Test func entriesFromDifferentSegmentsDoNotMix() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let first = newSegment(harnessA)
    let second = newSegment(harnessB)
    let session = newSession(segments: [first, second])
    try await store.saveMetadata(session)
    try await store.append(entry("a-um"), to: first.id, in: session.id)
    try await store.append(entry("b-um"), to: second.id, in: session.id)
    try await store.append(entry("a-dois"), to: first.id, in: session.id)

    let loaded = try await store.load(session.id)
    #expect(loaded.segments[0].entries.count == 2)
    #expect(loaded.segments[1].entries.count == 1)
    #expect(loaded.segments[1].harness == harnessB)
}

@Test func theFileOnDiskIsOneJSONObjectPerLine() async throws {

    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)
    let segment = newSegment()
    let session = newSession(segments: [segment])
    try await store.saveMetadata(session)
    try await store.append(entry("one"), to: segment.id, in: session.id)
    try await store.append(entry("two"), to: segment.id, in: session.id)

    let file = root.appendingPathComponent(session.id.uuidString)
        .appendingPathComponent("\(segment.id.uuidString).ndjson")
    let lines = try String(contentsOf: file, encoding: .utf8)
        .split(separator: "\n").filter { !$0.isEmpty }
    #expect(lines.count == 2)
    for line in lines {
        #expect((try? JSONSerialization.jsonObject(with: Data(line.utf8))) != nil)
    }
}

@Test func listReturnsASummaryPerSession() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let a = newSession(segments: [newSegment()])
    let b = newSession(segments: [newSegment()])
    try await store.saveMetadata(a)
    try await store.saveMetadata(b)

    let listing = try await store.list()
    #expect(listing.sessions.count == 2)
    #expect(Set(listing.sessions.map(\.id)) == Set([a.id, b.id]))
    #expect(listing.unreadable.isEmpty)
}

@Test func savingMetadataAgainDoesNotDisturbTheEntries() async throws {

    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)
    let segment = newSegment()
    var session = newSession(segments: [segment])
    try await store.saveMetadata(session)
    try await store.append(entry("one"), to: segment.id, in: session.id)

    session.title = "another title"
    try await store.saveMetadata(session)

    let loaded = try await store.load(session.id)
    #expect(loaded.title == "another title")
    #expect(loaded.allEntries.count == 1)
}

@Test func appendToAMissingSessionFailsWithSessionNotFound() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)
    let missingSessionID = UUID()

    await #expect(throws: TranscriptStoreError.sessionNotFound(missingSessionID)) {
        try await store.append(entry("one"), to: UUID(), in: missingSessionID)
    }
}

@Test func renamingDoesNotMoveUpdatedAtWhenTheConversationHasEntries() async throws {

    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)
    let segment = newSegment()
    var session = newSession(segments: [segment])
    try await store.saveMetadata(session)
    try await store.append(entry("one"), to: segment.id, in: session.id)

    let yesterday = Date(timeIntervalSinceNow: -86_400)
    let file = root.appendingPathComponent(
        "\(session.id.uuidString)/\(segment.id.uuidString).ndjson")
    try FileManager.default.setAttributes(
        [.modificationDate: yesterday], ofItemAtPath: file.path)

    session.title = "another title"
    try await store.saveMetadata(session)

    let summary = try #require(try await store.list().sessions.first)
    #expect(abs(summary.updatedAt.timeIntervalSince(yesterday)) < 2)
}

@Test func aSessionWithoutEntriesStillHasAnUpdatedAtFromItsMetadata() async throws {

    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)
    let session = newSession(segments: [newSegment()])
    try await store.saveMetadata(session)

    let summary = try #require(try await store.list().sessions.first)
    #expect(abs(summary.updatedAt.timeIntervalSinceNow) < 5)
}

@Test func appendToASegmentNotListedInTheSessionFailsWithSegmentNotFound() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)
    let segment = newSegment()
    let session = newSession(segments: [segment])
    try await store.saveMetadata(session)

    let strangerSegmentID = UUID()
    await #expect(throws: TranscriptStoreError.segmentNotFound(strangerSegmentID)) {
        try await store.append(entry("one"), to: strangerSegmentID, in: session.id)
    }
}

@Test func concurrentAppendsFromDifferentStoreInstancesDoNotCorruptOrLoseEntries() async throws {
    try await withTimeout(seconds: 20) {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let segment = newSegment()
        let session = newSession(segments: [segment])

        try await FileTranscriptStore(root: root).saveMetadata(session)

        let storeCount = 4
        let writersPerStore = 4
        let roundsPerWriter = 10

        let stores = (0..<storeCount).map { _ in FileTranscriptStore(root: root) }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for (storeIndex, store) in stores.enumerated() {
                for writerIndex in 0..<writersPerStore {
                    group.addTask {
                        for round in 0..<roundsPerWriter {
                            try await store.append(
                                entry("s\(storeIndex)-w\(writerIndex)-r\(round)"),
                                to: segment.id, in: session.id)
                        }
                    }
                }
            }
            try await group.waitForAll()
        }

        let expected = Set(
            (0..<storeCount).flatMap { storeIndex in
                (0..<writersPerStore).flatMap { writerIndex in
                    (0..<roundsPerWriter).map { round in "s\(storeIndex)-w\(writerIndex)-r\(round)" }
                }
            })

        let loaded = try await stores[0].load(session.id)
        let texts = loaded.allEntries.compactMap { e -> String? in
            if case .assistantText(let t) = e.kind { return t }
            return nil
        }

        #expect(texts.count == expected.count)
        #expect(Set(texts) == expected)
    }
}

@Test func deletingASessionRemovesItFromDiskAndListing() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let session = newSession(segments: [newSegment()])
    try await store.saveMetadata(session)
    #expect(try await store.list().sessions.count == 1)

    try await store.delete(session.id)

    #expect(try await store.list().sessions.isEmpty)
    await #expect(throws: TranscriptStoreError.sessionNotFound(session.id)) {
        _ = try await store.load(session.id)
    }
}

@Test func deletingAnUnknownSessionThrowsSessionNotFound() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)
    let ghost = UUID()
    await #expect(throws: TranscriptStoreError.sessionNotFound(ghost)) {
        try await store.delete(ghost)
    }
}
