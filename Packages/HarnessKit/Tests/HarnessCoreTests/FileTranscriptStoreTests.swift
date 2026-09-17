import Testing
import Foundation
@testable import HarnessCore

// Dois ids neutros, mesmo padrão de SessionTests.swift: `HarnessID.claudeCode`
// mora em `ClaudeHarness` (spec §7.1; `harnessCoreNeverNamesASpecificHarness`
// em ModuleBoundaryTests.swift), e este alvo de teste não depende de
// `ClaudeHarness`.
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
    Segment(harness: harness, harnessSessionID: UUID(), model: "m")
}

@Test func aSessionRoundTripsThroughDisk() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)

    let segment = newSegment()
    let session = newSession(segments: [segment])
    try await store.saveMetadata(session)
    try await store.append(entry("um"), to: segment.id, in: session.id)
    try await store.append(entry("dois"), to: segment.id, in: session.id)

    let loaded = try await store.load(session.id)
    #expect(loaded.id == session.id)
    #expect(loaded.title == "uma conversa")
    #expect(loaded.workingDirectory.path == "/tmp/repo")
    #expect(loaded.segments.count == 1)
    let texts = loaded.allEntries.compactMap { e -> String? in
        if case .assistantText(let t) = e.kind { return t }
        return nil
    }
    #expect(texts == ["um", "dois"])
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
    try await store.append(entry("claude-um"), to: first.id, in: session.id)
    try await store.append(entry("codex-um"), to: second.id, in: session.id)
    try await store.append(entry("claude-dois"), to: first.id, in: session.id)

    let loaded = try await store.load(session.id)
    #expect(loaded.segments[0].entries.count == 2)
    #expect(loaded.segments[1].entries.count == 1)
    #expect(loaded.segments[1].harness == harnessB)
}

@Test func theFileOnDiskIsOneJSONObjectPerLine() async throws {
    // O formato tem que ser legível com `cat` quando algo der errado (spec §4.3).
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)
    let segment = newSegment()
    let session = newSession(segments: [segment])
    try await store.saveMetadata(session)
    try await store.append(entry("um"), to: segment.id, in: session.id)
    try await store.append(entry("dois"), to: segment.id, in: session.id)

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

    let summaries = try await store.list()
    #expect(summaries.count == 2)
    #expect(Set(summaries.map(\.id)) == Set([a.id, b.id]))
}

@Test func savingMetadataAgainDoesNotDisturbTheEntries() async throws {
    // Renomear a sessão não pode apagar o transcript.
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTranscriptStore(root: root)
    let segment = newSegment()
    var session = newSession(segments: [segment])
    try await store.saveMetadata(session)
    try await store.append(entry("um"), to: segment.id, in: session.id)

    session.title = "outro título"
    try await store.saveMetadata(session)

    let loaded = try await store.load(session.id)
    #expect(loaded.title == "outro título")
    #expect(loaded.allEntries.count == 1)
}
