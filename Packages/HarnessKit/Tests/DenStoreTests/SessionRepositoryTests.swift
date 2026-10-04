import Testing
import Foundation
import HarnessCore
import DenStore
import SQLiteKit

@Test func aSessionComesBackExactlyAsItWasSaved() async throws {
    let store = try DenStore.inMemory()
    let session = try await saved(in: store)
    let entries = ["um", "dois", "três"].map(spoken)
    for entry in entries {
        try await store.sessions.append(entry, to: session.segments[0].id, in: session.id)
    }

    var expected = session
    expected.segments[0].entries = entries
    #expect(try await store.sessions.load(session.id) == expected)
}

@Test func eachSegmentKeepsItsOwnEntries() async throws {
    let store = try DenStore.inMemory()
    let session = try await saved(conversation(segments: [stretch(on: harnessA), stretch(on: harnessB)]),
                                  in: store)
    let (first, second) = (session.segments[0].id, session.segments[1].id)
    try await store.sessions.append(spoken("a-um"), to: first, in: session.id)
    try await store.sessions.append(spoken("b-um"), to: second, in: session.id)
    try await store.sessions.append(spoken("a-dois"), to: first, in: session.id)

    let loaded = try await store.sessions.load(session.id)

    #expect(loaded.segments.map(\.harness) == [harnessA, harnessB])
    #expect(texts(of: Session(title: "", workingDirectory: loaded.workingDirectory,
                              segments: [loaded.segments[0]])) == ["a-um", "a-dois"])
    #expect(loaded.segments[1].entries.count == 1)
}

@Test func whatASegmentCarriesSurvives() async throws {
    let store = try DenStore.inMemory()
    let anchor = UUID()
    let rich = Segment(harness: harnessB, harnessSessionID: "ses_42", model: "opus",
                       usage: UsageTotals(inputTokens: 10, outputTokens: 20, cacheReadTokens: 30,
                                          cacheCreationTokens: 40, costUSD: 1.25),
                       seededBy: .replay(throughEntry: anchor),
                       context: ContextUsage(usedTokens: 500, windowTokens: 2000, slices: []))
    let session = try await saved(conversation(segments: [stretch(), rich]), in: store)

    let loaded = try await store.sessions.load(session.id)

    #expect(loaded.segments[1] == rich)
    #expect(loaded.segments[0].seededBy == nil)
    #expect(loaded.segments[0].context == nil)
}

@Test func savingTheMetadataAgainKeepsTheEntries() async throws {
    let store = try DenStore.inMemory()
    var session = try await saved(in: store)
    try await store.sessions.append(spoken("um"), to: session.segments[0].id, in: session.id)

    session.title = "outro título"
    session.workingDirectory = URL(fileURLWithPath: "/tmp/outro")
    try await store.sessions.saveMetadata(session)

    let loaded = try await store.sessions.load(session.id)
    #expect(loaded.title == "outro título")
    #expect(loaded.workingDirectory == URL(fileURLWithPath: "/tmp/outro"))
    #expect(texts(of: loaded) == ["um"])
}

@Test func aSegmentDroppedFromTheMetadataTakesItsEntriesAlong() async throws {
    let store = try DenStore.inMemory()
    var session = try await saved(conversation(segments: [stretch(), stretch(on: harnessB)]), in: store)
    try await store.sessions.append(spoken("fica"), to: session.segments[0].id, in: session.id)
    try await store.sessions.append(spoken("vai"), to: session.segments[1].id, in: session.id)

    session.segments.removeLast()
    try await store.sessions.saveMetadata(session)

    let loaded = try await store.sessions.load(session.id)
    #expect(loaded.segments.map(\.id) == session.segments.map(\.id))
    #expect(texts(of: loaded) == ["fica"])
    #expect(try await store.sessions.list().first?.entryCount == 1)
}

@Test func segmentsSavedInANewOrderComeBackInThatOrder() async throws {
    let store = try DenStore.inMemory()
    var session = try await saved(conversation(segments: [stretch(), stretch(on: harnessB), stretch()]),
                                  in: store)

    session.segments.reverse()
    try await store.sessions.saveMetadata(session)

    #expect(try await store.sessions.load(session.id).segments.map(\.id) == session.segments.map(\.id))
}

@Test func appendingToAnUnknownSessionFails() async throws {
    let store = try DenStore.inMemory()
    let ghost = UUID()

    await #expect(throws: SessionRepositoryError.sessionNotFound(ghost)) {
        try await store.sessions.append(spoken("um"), to: UUID(), in: ghost)
    }
}

@Test func appendingToASegmentTheSessionDoesNotOwnFails() async throws {
    let store = try DenStore.inMemory()
    let session = try await saved(in: store)
    let other = try await saved(in: store)
    let stranger = UUID()

    await #expect(throws: SessionRepositoryError.segmentNotFound(stranger)) {
        try await store.sessions.append(spoken("um"), to: stranger, in: session.id)
    }
    await #expect(throws: SessionRepositoryError.segmentNotFound(other.segments[0].id)) {
        try await store.sessions.append(spoken("um"), to: other.segments[0].id, in: session.id)
    }
    #expect(try await store.sessions.load(other.id).allEntries.isEmpty)
}

@Test func appendingTheSameEntryTwiceKeepsOne() async throws {
    let store = try DenStore.inMemory()
    let session = try await saved(in: store)
    let entry = spoken("uma vez")

    try await store.sessions.append(entry, to: session.segments[0].id, in: session.id)
    try await store.sessions.append(entry, to: session.segments[0].id, in: session.id)

    #expect(try await store.sessions.load(session.id).allEntries == [entry])
}

@Test func anEntryWhosePayloadCannotBeReadIsSkipped() async throws {
    let scratch = try ScratchStore()
    defer { scratch.remove() }
    let store = try scratch.open().repositories
    let session = try await saved(in: store)
    let broken = spoken("quebrada")
    for entry in [spoken("antes"), broken, spoken("depois")] {
        try await store.sessions.append(entry, to: session.segments[0].id, in: session.id)
    }

    try scratch.raw().write {
        try $0.execute("UPDATE entries SET payload = '{nope' WHERE id = ?", [.text(broken.id.uuidString)])
    }

    #expect(try await texts(of: store.sessions.load(session.id)) == ["antes", "depois"])
    #expect(try await store.sessions.list().first?.entryCount == 3)
}

@Test func listSummarizesEverySession() async throws {
    let clock = TestClock()
    let store = try DenStore.inMemory(now: { clock.now })
    let first = Segment(harness: harnessA, harnessSessionID: "a", model: "m",
                        usage: UsageTotals(inputTokens: 1, outputTokens: 2, costUSD: 0.5))
    let second = Segment(harness: harnessB, harnessSessionID: "b", model: "m",
                         usage: UsageTotals(inputTokens: 10, outputTokens: 20, costUSD: 0.25))
    let session = try await saved(conversation("resumida", in: "/code/api", segments: [first, second]),
                                  in: store)
    try await store.sessions.append(spoken("um"), to: first.id, in: session.id)
    try await store.sessions.append(spoken("dois"), to: second.id, in: session.id)

    let summaries = try await store.sessions.list()

    #expect(summaries == [SessionSummary(
        id: session.id, title: "resumida", workingDirectory: URL(fileURLWithPath: "/code/api"),
        harnesses: [harnessA, harnessB],
        usage: UsageTotals(inputTokens: 11, outputTokens: 22, costUSD: 0.75),
        entryCount: 2, updatedAt: epoch)])
}

@Test func listPutsTheMostRecentlyTouchedSessionFirst() async throws {
    let clock = TestClock()
    let store = try DenStore.inMemory(now: { clock.now })
    let old = try await saved(conversation("antiga"), in: store)
    clock.advance(by: 60)
    let fresh = try await saved(conversation("nova"), in: store)
    #expect(try await store.sessions.list().map(\.title) == ["nova", "antiga"])

    clock.advance(by: 60)
    try await store.sessions.append(spoken("acordou"), to: old.segments[0].id, in: old.id)

    let summaries = try await store.sessions.list()
    #expect(summaries.map(\.id) == [old.id, fresh.id])
    #expect(summaries.map(\.updatedAt) == [epoch.addingTimeInterval(120), epoch.addingTimeInterval(60)])
}

@Test func sessionsTouchedAtTheSameMomentListByIdentifier() async throws {
    let clock = TestClock()
    let store = try DenStore.inMemory(now: { clock.now })
    var ids: [UUID] = []
    for _ in 0..<6 { ids.append(try await saved(in: store).id) }

    #expect(try await store.sessions.list().map(\.id.uuidString) == ids.map(\.uuidString).sorted())
}

@Test func renamingDoesNotCountAsActivity() async throws {
    let clock = TestClock()
    let store = try DenStore.inMemory(now: { clock.now })
    var session = try await saved(in: store)

    clock.advance(by: 3600)
    session.title = "renomeada"
    try await store.sessions.saveMetadata(session)

    #expect(try await store.sessions.list().map(\.updatedAt) == [epoch])
}

@Test func deletingASessionRemovesEverythingUnderIt() async throws {
    let scratch = try ScratchStore()
    defer { scratch.remove() }
    let store = try scratch.open().repositories
    let doomed = try await saved(in: store)
    let kept = try await saved(conversation("fica"), in: store)
    try await store.sessions.append(spoken("um"), to: doomed.segments[0].id, in: doomed.id)
    try await store.sessions.append(spoken("dois"), to: kept.segments[0].id, in: kept.id)

    try await store.sessions.delete(doomed.id)

    #expect(try await store.sessions.list().map(\.id) == [kept.id])
    await #expect(throws: SessionRepositoryError.sessionNotFound(doomed.id)) {
        _ = try await store.sessions.load(doomed.id)
    }
    let leftovers = try scratch.raw().read {
        try $0.query("SELECT (SELECT COUNT(*) FROM segments), (SELECT COUNT(*) FROM entries)") { ($0[0], $0[1]) }
    }
    #expect(leftovers.first?.0 == .integer(1))
    #expect(leftovers.first?.1 == .integer(1))
}

@Test func deletingAnUnknownSessionFails() async throws {
    let store = try DenStore.inMemory()
    let ghost = UUID()

    await #expect(throws: SessionRepositoryError.sessionNotFound(ghost)) {
        try await store.sessions.delete(ghost)
    }
}

@Test func appendingAfterADeleteDoesNotBringTheSessionBack() async throws {
    let store = try DenStore.inMemory()
    let session = try await saved(in: store)
    try await store.sessions.delete(session.id)

    await #expect(throws: SessionRepositoryError.sessionNotFound(session.id)) {
        try await store.sessions.append(spoken("tarde demais"), to: session.segments[0].id, in: session.id)
    }
    #expect(try await store.sessions.list().isEmpty)
}

@Test func aLongTranscriptWithAHugeEntryRoundTrips() async throws {
    let store = try DenStore.inMemory()
    let session = try await saved(in: store)
    let huge = String(repeating: "x", count: 2_000_000)
    let spokenTexts = (0..<2000).map { "linha \($0)" } + [huge]
    for text in spokenTexts {
        try await store.sessions.append(spoken(text), to: session.segments[0].id, in: session.id)
    }

    #expect(try await texts(of: store.sessions.load(session.id)) == spokenTexts)
    #expect(try await store.sessions.list().first?.entryCount == 2001)
}

@Test func awkwardTextSurvives() async throws {
    let store = try DenStore.inMemory()
    let title = "it's \"quoted\"; DROP TABLE sessions; -- 🧨\nsegunda linha"
    let session = try await saved(conversation(title, in: "/Users/gabi/Área de trabalho/meu projeto"),
                                  in: store)
    try await store.sessions.append(spoken("olá 'mundo' 👋 %s ?"), to: session.segments[0].id, in: session.id)

    let loaded = try await store.sessions.load(session.id)

    #expect(loaded.title == title)
    #expect(loaded.workingDirectory.path == "/Users/gabi/Área de trabalho/meu projeto")
    #expect(texts(of: loaded) == ["olá 'mundo' 👋 %s ?"])
    #expect(try await store.sessions.list().map(\.workingDirectory) == [session.workingDirectory])
}

@Test func twoStoresOnTheSameFileSeeEachOthersWrites() async throws {
    let scratch = try ScratchStore()
    defer { scratch.remove() }
    let one = try scratch.open().repositories
    let two = try scratch.open().repositories
    let session = try await saved(in: one)

    try await two.sessions.append(spoken("do outro processo"), to: session.segments[0].id, in: session.id)
    try await one.sessions.append(spoken("deste"), to: session.segments[0].id, in: session.id)

    #expect(try await texts(of: one.sessions.load(session.id)) == ["do outro processo", "deste"])
    #expect(try await texts(of: two.sessions.load(session.id)) == ["do outro processo", "deste"])
}

@Test func manyWritersAtOnceLoseNothing() async throws {
    let scratch = try ScratchStore()
    defer { scratch.remove() }
    let stores = try (0..<4).map { _ in try scratch.open().repositories }
    let session = try await saved(in: stores[0])
    let segment = session.segments[0].id

    try await withThrowingTaskGroup(of: Void.self) { group in
        for (index, store) in stores.enumerated() {
            for writer in 0..<4 {
                group.addTask {
                    for round in 0..<10 {
                        try await store.sessions.append(spoken("s\(index)-w\(writer)-r\(round)"),
                                                        to: segment, in: session.id)
                    }
                }
            }
        }
        try await group.waitForAll()
    }

    let written = try await texts(of: stores[0].sessions.load(session.id))
    #expect(written.count == 160)
    #expect(Set(written).count == 160)
}
