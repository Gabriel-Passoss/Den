import Testing
import Foundation
import HarnessCore
@testable import ClaudeHarness

private let clock = Date(timeIntervalSince1970: 1_000_000)

private func mapFixture(_ name: String) throws -> MappedOutput {
    let url = try #require(Bundle.module.url(
        forResource: "Fixtures/\(name)", withExtension: "ndjson"))
    let mapper = ClaudeEventMapper(now: { clock })
    var all = MappedOutput.empty
    for line in try String(contentsOf: url, encoding: .utf8)
        .split(separator: "\n") where !line.isEmpty {
        let out = mapper.map(line: Data(line.utf8))
        all.events += out.events
        all.entries += out.entries
    }
    return all
}

private func kindName(_ kind: TranscriptEntry.Kind) -> String {
    switch kind {
    case .userMessage: return "userMessage"
    case .assistantText: return "assistantText"
    case .assistantThinking: return "assistantThinking"
    case .toolCall: return "toolCall"
    case .toolResult: return "toolResult"
    case .permissionRequest: return "permissionRequest"
    case .permissionDecision: return "permissionDecision"
    case .systemNotice: return "systemNotice"
    case .turnResult: return "turnResult"
    case .contextCompacted: return "contextCompacted"
    case .unrecognized(let discriminator, _): return "unrecognized(\(discriminator))"
    }
}

@Test(arguments: [
    ("hello", 4, 8),
    ("tool-use", 6, 47),
    ("permission-request", 6, 4),
    ("permission-denied", 27, 240),
])
func everyFixtureMapsToTheMeasuredCounts(
    fixture: (name: String, entries: Int, events: Int)
) throws {
    let out = try mapFixture(fixture.name)
    #expect(out.entries.count == fixture.entries)
    #expect(out.events.count == fixture.events)
}

@Test func theDeltaStreamNeverReachesTheTranscript() throws {
    let out = try mapFixture("permission-denied")
    #expect(out.entries.count == 27)
    #expect(out.events.count == 240)

    let texts = out.entries.compactMap { entry -> String? in
        guard case .assistantText(let text) = entry.kind else { return nil }
        return text
    }
    #expect(texts.count == 1, "um texto consolidado por turno, não um por delta")
}

@Test func theOrderOfKindsPreservesTheStory() throws {
    let kinds = try mapFixture("permission-denied").entries.map { kindName($0.kind) }
    #expect(kinds == [
        "systemNotice", "systemNotice",
        "toolCall", "permissionDecision", "toolResult", "assistantThinking",
        "toolCall", "permissionDecision", "toolResult", "assistantThinking",
        "toolCall", "permissionDecision", "toolResult", "assistantThinking",
        "toolCall", "permissionDecision", "toolResult", "assistantThinking",
        "toolCall", "permissionDecision", "toolResult", "assistantThinking",
        "toolCall", "permissionDecision", "toolResult",
        "assistantText", "turnResult",
    ])
}

@Test(arguments: ["hello", "tool-use", "permission-request", "permission-denied"])
func theHappyPathFixturesShareTheSameSpine(name: String) throws {
    let kinds = try mapFixture(name).entries.map { kindName($0.kind) }
    #expect(kinds.first == "systemNotice", "toda sessão abre com um system/init")
    #expect(kinds.last == "turnResult", "e fecha com o result do turno")
}

@Test(arguments: ["hello", "tool-use", "permission-request", "permission-denied"])
func noFixtureLineDegrades(name: String) throws {
    for entry in try mapFixture(name).entries {
        if case .unrecognized(let discriminator, _) = entry.kind {
            Issue.record("\(name): forma não prevista \(discriminator)")
        }
    }
}

@Test(arguments: ["tool-use", "permission-request", "permission-denied"])
func everyToolResultPointsAtAToolCallInTheSameTranscript(name: String) throws {
    let entries = try mapFixture(name).entries
    let callIDs = Set(entries.compactMap { entry -> String? in
        guard case .toolCall(let call) = entry.kind else { return nil }
        return call.id
    })
    #expect(!callIDs.isEmpty)
    for entry in entries {
        guard case .toolResult(let result) = entry.kind else { continue }
        #expect(callIDs.contains(result.callID), "resultado órfão: \(result.callID)")
    }
}

@Test func everyDenialPointsAtTheCallItBlocked() throws {
    let entries = try mapFixture("permission-denied").entries
    let callIDs = Set(entries.compactMap { entry -> String? in
        guard case .toolCall(let call) = entry.kind else { return nil }
        return call.id
    })
    var decisions = 0
    for entry in entries {
        guard case .permissionDecision(let requestID, let decision) = entry.kind else { continue }
        decisions += 1
        #expect(callIDs.contains(requestID), "negação órfã: \(requestID)")
        guard case .deny = decision else { Issue.record("esperava .deny"); continue }
    }
    #expect(decisions == 6)
}

@Test func theMappedTranscriptSurvivesTheStore() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mapper-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let entries = try mapFixture("permission-denied").entries
    let segment = Segment(harness: .claudeCode, harnessSessionID: UUID().uuidString, model: "claude-opus-5")
    let session = Session(title: "corpus", workingDirectory: root, segments: [segment])

    let store = FileTranscriptStore(root: root)
    try await store.saveMetadata(session)
    for entry in entries {
        try await store.append(entry, to: segment.id, in: session.id)
    }

    let loaded = try await store.load(session.id)
    #expect(loaded.allEntries.count == entries.count)
    #expect(loaded.allEntries.map(\.kind) == entries.map(\.kind))
    #expect(loaded.allEntries.map(\.raw) == entries.map(\.raw))
    #expect(loaded.allEntries.map(\.id) == entries.map(\.id))

    for (loadedEntry, original) in zip(loaded.allEntries, entries) {
        #expect(abs(loadedEntry.timestamp.timeIntervalSince(original.timestamp)) < 1)
    }
}
