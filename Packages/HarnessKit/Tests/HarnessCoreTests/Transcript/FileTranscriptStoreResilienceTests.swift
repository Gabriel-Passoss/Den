import Testing
import Foundation
@testable import HarnessCore

private let harnessA = HarnessID(rawValue: "harness-a")

private let when = Date(timeIntervalSince1970: 1_700_000_000)

private func makeRoot() throws -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("resilience-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func entry(_ text: String) -> TranscriptEntry {
    TranscriptEntry(timestamp: when, kind: .assistantText(text), raw: .null)
}

private func texts(of session: Session) -> [String] {
    session.allEntries.compactMap { e -> String? in
        if case .assistantText(let t) = e.kind { return t }
        return nil
    }
}

@Test func aTruncatedLastLineEndingOnACharacterBoundaryCostsOneEntry() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let segment = Segment(harness: harnessA, harnessSessionID: UUID().uuidString, model: "m")
    let session = Session(title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
                          segments: [segment])
    try await store.saveMetadata(session)
    try await store.append(entry("one"), to: segment.id, in: session.id)
    try await store.append(entry("two"), to: segment.id, in: session.id)

    let file = root.appendingPathComponent(session.id.uuidString)
        .appendingPathComponent("\(segment.id.uuidString).ndjson")
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(#"{"id":"unfinis"#.utf8))
    try handle.close()

    let loaded = try await store.load(session.id)
    let texts = loaded.allEntries.compactMap { e -> String? in
        if case .assistantText(let t) = e.kind { return t }
        return nil
    }
    #expect(texts == ["one", "two"], "half a line must not cost the whole conversation")
}

@Test func aCorruptLineInTheMiddleDoesNotHideTheOnesAfterIt() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let segment = Segment(harness: harnessA, harnessSessionID: UUID().uuidString, model: "m")
    let session = Session(title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
                          segments: [segment])
    try await store.saveMetadata(session)
    try await store.append(entry("one"), to: segment.id, in: session.id)

    let file = root.appendingPathComponent(session.id.uuidString)
        .appendingPathComponent("\(segment.id.uuidString).ndjson")
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("{junk}\n".utf8))
    try handle.close()
    try await store.append(entry("three"), to: segment.id, in: session.id)

    let loaded = try await store.load(session.id)
    let texts = loaded.allEntries.compactMap { e -> String? in
        if case .assistantText(let t) = e.kind { return t }
        return nil
    }
    #expect(texts == ["one", "three"])
}

@Test func aTruncatedTailDoesNotSwallowTheEntryAppendedAfterARestart() async throws {

    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let segment = Segment(harness: harnessA, harnessSessionID: UUID().uuidString, model: "m")
    let session = Session(title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
                          segments: [segment])
    try await store.saveMetadata(session)
    try await store.append(entry("one"), to: segment.id, in: session.id)

    let file = root.appendingPathComponent(session.id.uuidString)
        .appendingPathComponent("\(segment.id.uuidString).ndjson")
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(#"{"id":"partial"#.utf8))
    try handle.close()

    try await store.append(entry("three"), to: segment.id, in: session.id)

    let loaded = try await store.load(session.id)
    let texts = loaded.allEntries.compactMap { e -> String? in
        if case .assistantText(let t) = e.kind { return t }
        return nil
    }
    #expect(texts == ["one", "three"],
             "the new entry must not be lost along with the truncated fragment")
}

@Test func listCountsRawLinesWhileLoadCountsDecodableEntries() async throws {

    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let segment = Segment(harness: harnessA, harnessSessionID: UUID().uuidString, model: "m")
    let session = Session(title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
                          segments: [segment])
    try await store.saveMetadata(session)
    try await store.append(entry("one"), to: segment.id, in: session.id)
    try await store.append(entry("two"), to: segment.id, in: session.id)

    let file = root.appendingPathComponent(session.id.uuidString)
        .appendingPathComponent("\(segment.id.uuidString).ndjson")
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(#"{"id":"partial"#.utf8))
    try handle.close()

    let listing = try await store.list()
    let loaded = try await store.load(session.id)

    #expect(listing.sessions.first?.entryCount == 3,
             "list() conta a linha truncada como uma linha em disco")
    #expect(loaded.allEntries.count == 2,
             "load() only counts what actually decoded")
}

@Test func aSegmentWithNoFileYetLoadsAsEmpty() async throws {

    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let segment = Segment(harness: harnessA, harnessSessionID: UUID().uuidString, model: "m")
    let session = Session(title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
                          segments: [segment])
    try await store.saveMetadata(session)

    let loaded = try await store.load(session.id)
    #expect(loaded.segments.first?.entries.isEmpty == true)
}

@Test func loadingAnUnknownSessionSaysSoInsteadOfCrashing() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)
    let missing = UUID()
    await #expect(throws: TranscriptStoreError.sessionNotFound(missing)) {
        _ = try await store.load(missing)
    }
}

@Test func listSkipsADirectoryWithoutValidMetadata() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let good = Session(title: "boa", workingDirectory: URL(fileURLWithPath: "/tmp"), segments: [])
    try await store.saveMetadata(good)

    let junk = root.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: junk, withIntermediateDirectories: true)
    try Data("{not json".utf8).write(to: junk.appendingPathComponent("session.json"))
    try FileManager.default.createDirectory(
        at: root.appendingPathComponent("nem-diretorio-de-sessao"),
        withIntermediateDirectories: true)

    let listing = try await store.list()
    #expect(listing.sessions.map(\.id) == [good.id])

    #expect(listing.unreadable.count == 1)
}

@Test func listOnAnEmptyOrMissingRootIsEmptyNotAnError() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(try await FileTranscriptStore(root: root).list() == SessionListing())

    let missing = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("nao-existe-\(UUID().uuidString)")
    #expect(try await FileTranscriptStore(root: missing).list() == SessionListing())
}

@Test func aTailCutInsideAMultiByteCharacterCostsOneEntryNotTheWholeSession() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let segment = Segment(harness: harnessA, harnessSessionID: UUID().uuidString, model: "m")
    let session = Session(title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
                          segments: [segment])
    try await store.saveMetadata(session)
    try await store.append(entry("one"), to: segment.id, in: session.id)
    try await store.append(entry("two"), to: segment.id, in: session.id)
    try await store.append(entry("three"), to: segment.id, in: session.id)

    let file = root.appendingPathComponent(session.id.uuidString)
        .appendingPathComponent("\(segment.id.uuidString).ndjson")
    var fragment = Data(#"{"id":"11111111-1111-1111-1111-111111111111","kind":{"assistantText":{"_0":"corre"#.utf8)
    fragment.append(0xC3)
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: fragment)
    try handle.close()

    let asOneString = try? String(contentsOf: file, encoding: .utf8)
    #expect(asOneString == nil,
             "the fixture must cut INSIDE the character, not on a boundary")

    let afterCrash = try await store.load(session.id)
    #expect(texts(of: afterCrash) == ["one", "two", "three"],
             "half a character must not cost the whole conversation")

    try await store.append(entry("four"), to: segment.id, in: session.id)
    let afterRestart = try await store.load(session.id)
    #expect(texts(of: afterRestart) == ["one", "two", "three", "four"],
             "the entry written after the restart must not stay invisible")

    let listing = try await store.list()
    #expect(listing.sessions.first?.entryCount == 5,
             "quatro linhas boas mais a cauda cortada")
}

// MARK: - session.json: a damaged session must not vanish silently

private let futureHandoffJSON = #"{"summarizeWithModel":{"model":"m-9","tokens":800}}"#

private func sessionJSONWithFutureHandoff(session: Session, segment: Segment) -> Data {
    Data(#"""
    {"id":"\#(session.id.uuidString)","segments":[{"entries":[],"harness":"harness-a","harnessSessionID":"\#(segment.harnessSessionID)","id":"\#(segment.id.uuidString)","model":"m","seededBy":\#(futureHandoffJSON),"usage":{"cacheCreationTokens":0,"cacheReadTokens":0,"costUSD":0,"inputTokens":0,"outputTokens":0}}],"title":"t","workingDirectory":"file:///tmp"}
    """#.utf8)
}

@Test func aSessionSeededByAFutureHandoffStillLoadsListsAndAppends() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let segment = Segment(harness: harnessA, harnessSessionID: UUID().uuidString, model: "m")
    let session = Session(title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
                          segments: [segment])
    try await store.saveMetadata(session)

    try sessionJSONWithFutureHandoff(session: session, segment: segment)
        .write(to: root.appendingPathComponent(session.id.uuidString)
            .appendingPathComponent("session.json"))

    let loaded = try await store.load(session.id)
    #expect(loaded.id == session.id)
    guard case .unrecognized(let discriminator, let payload) =
            loaded.segments.first?.seededBy else {
        Issue.record("esperava .unrecognized, achei \(String(describing: loaded.segments.first?.seededBy))")
        return
    }
    #expect(discriminator == "summarizeWithModel")
    #expect(payload["model"] == .string("m-9"))

    let listing = try await store.list()
    #expect(listing.sessions.map(\.id) == [session.id])
    #expect(listing.unreadable.isEmpty)

    try await store.append(entry("depois"), to: segment.id, in: session.id)
    #expect(texts(of: try await store.load(session.id)) == ["depois"])
}

@Test func reencodingAFutureHandoffKeepsItsOriginalNameNotTheWordUnrecognized() async throws {

    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let segment = Segment(harness: harnessA, harnessSessionID: UUID().uuidString, model: "m")
    let session = Session(title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
                          segments: [segment])
    try await store.saveMetadata(session)
    let metadata = root.appendingPathComponent(session.id.uuidString)
        .appendingPathComponent("session.json")
    try sessionJSONWithFutureHandoff(session: session, segment: segment).write(to: metadata)

    var renamed = try await store.load(session.id)
    renamed.title = "another title"
    try await store.saveMetadata(renamed)

    let rewritten = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: metadata))
    let seededBy = rewritten["segments"]?.arrayValue?.first?["seededBy"]
    #expect(seededBy?["summarizeWithModel"]?["model"] == .string("m-9"))
    #expect(seededBy?["unrecognized"] == nil)
}

@Test func aSessionWithUnreadableMetadataIsReportedNotDroppedFromTheList() async throws {

    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let good = Session(title: "boa", workingDirectory: URL(fileURLWithPath: "/tmp"), segments: [])
    try await store.saveMetadata(good)

    let damagedID = UUID()
    let damaged = root.appendingPathComponent(damagedID.uuidString)
    try FileManager.default.createDirectory(at: damaged, withIntermediateDirectories: true)
    try Data(#"{"id":"not a valid session"#.utf8)
        .write(to: damaged.appendingPathComponent("session.json"))

    try FileManager.default.createDirectory(
        at: root.appendingPathComponent("nem-diretorio-de-sessao"),
        withIntermediateDirectories: true)

    let listing = try await store.list()
    #expect(listing.sessions.map(\.id) == [good.id],
             "the good session stays listed — a damaged one does not take the list down")
    #expect(listing.unreadable.count == 1,
             "the damaged session is reported, not omitted")
    #expect(listing.unreadable.first?.id == damagedID)

    #expect(listing.unreadable.first?.location.resolvingSymlinksInPath().path
            == damaged.resolvingSymlinksInPath().path)
    #expect(listing.unreadable.first?.reason.isEmpty == false)
}

// MARK: - updatedAt follows the transcript, not just the metadata

@Test func updatedAtFollowsTheTranscriptAndNotOnlyTheMetadata() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let segment = Segment(harness: harnessA, harnessSessionID: UUID().uuidString, model: "m")
    let session = Session(title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
                          segments: [segment])
    try await store.saveMetadata(session)
    try await store.append(entry("one"), to: segment.id, in: session.id)

    let directory = root.appendingPathComponent(session.id.uuidString)
    let oldMetadata = Date(timeIntervalSince1970: 1_000_000_000)
    let recentAppend = Date(timeIntervalSince1970: 1_900_000_000)
    try FileManager.default.setAttributes(
        [.modificationDate: oldMetadata],
        ofItemAtPath: directory.appendingPathComponent("session.json").path)
    try FileManager.default.setAttributes(
        [.modificationDate: recentAppend],
        ofItemAtPath: directory.appendingPathComponent("\(segment.id.uuidString).ndjson").path)

    let listing = try await store.list()
    let updatedAt = try #require(listing.sessions.first?.updatedAt)
    #expect(abs(updatedAt.timeIntervalSince(recentAppend)) < 0.001,
             "updatedAt must come from the segment, the file append actually touches")
}

@Test func updatedAtStillComesFromTheMetadataWhenNoSegmentHasBeenWrittenYet() async throws {

    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let session = Session(title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
                          segments: [Segment(harness: harnessA, harnessSessionID: UUID().uuidString, model: "m")])
    try await store.saveMetadata(session)
    let created = Date(timeIntervalSince1970: 1_500_000_000)
    try FileManager.default.setAttributes(
        [.modificationDate: created],
        ofItemAtPath: root.appendingPathComponent(session.id.uuidString)
            .appendingPathComponent("session.json").path)

    let updatedAt = try #require(try await store.list().sessions.first?.updatedAt)
    #expect(abs(updatedAt.timeIntervalSince(created)) < 0.001)
}

@Test func listPutsTheMostRecentlyTouchedSessionFirst() async throws {

    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    var ids: [UUID] = []

    for stamp in [1_200_000_000.0, 1_900_000_000.0, 1_500_000_000.0] {
        let session = Session(title: "t", workingDirectory: URL(fileURLWithPath: "/tmp"),
                              segments: [])
        try await store.saveMetadata(session)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: stamp)],
            ofItemAtPath: root.appendingPathComponent(session.id.uuidString)
                .appendingPathComponent("session.json").path)
        ids.append(session.id)
    }

    let listed = try await store.list().sessions.map(\.id)
    #expect(listed == [ids[1], ids[2], ids[0]])
}
