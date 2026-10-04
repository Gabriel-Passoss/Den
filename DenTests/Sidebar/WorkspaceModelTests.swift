import Testing
import Foundation
import HarnessCore
@testable import Den

// MARK: - Folder persistence

@Test func foldersSurviveANewModelOnTheSameStore() async throws {
    try await withWorkspace { harness in
        harness.model.addFolder()
        let created = try #require(harness.model.folders.first)
        harness.model.renameFolder(created.id, to: "Backend")

        let reopened = harness.reopened()
        #expect(reopened.folders.map(\.name) == ["Backend"])
        #expect(reopened.folders.map(\.id) == [created.id])
    }
}

@Test func membershipAndOrderSurviveTheSameWay() async throws {
    try await withWorkspace { harness in
        let session = storedSession("guardada")
        try await harness.store.saveMetadata(session)
        harness.model.addFolder()
        let folder = try #require(harness.model.folders.first)
        harness.model.membership = [session.id.uuidString: folder.id]
        harness.model.sessionOrder = [session.id.uuidString]

        let reopened = harness.reopened()
        #expect(reopened.membership == [session.id.uuidString: folder.id])
        #expect(reopened.sessionOrder == [session.id.uuidString])
    }
}

@Test func aPlaceInTheSidebarThatPointsNowhereIsNotKept() async throws {
    try await withWorkspace { harness in
        harness.model.membership = [UUID().uuidString: "pasta-que-não-existe"]
        harness.model.sessionOrder = [UUID().uuidString, "nem é um identificador"]

        let reopened = harness.reopened()
        #expect(reopened.membership.isEmpty)
        #expect(reopened.sessionOrder.isEmpty)
    }
}

// MARK: - Ordering

@Test func sessionsWithoutAStoredOrderFallBackToRecency() async throws {
    try await withWorkspace { harness in
        harness.model.summaries = [summary("older", updated: 100),
                                   summary("newer", updated: 200)]
        #expect(harness.model.looseSessions.map(\.title) == ["newer", "older"])
    }
}

@Test func theStoredOrderOverridesRecency() async throws {
    try await withWorkspace { harness in
        let old = summary("old", updated: 100)
        let new = summary("new", updated: 200)
        harness.model.summaries = [new, old]
        harness.model.sessionOrder = [old.id.uuidString, new.id.uuidString]
        #expect(harness.model.looseSessions.map(\.title) == ["old", "new"])
    }
}

@Test func aSessionMissingFromTheOrderSortsAhead() async throws {
    try await withWorkspace { harness in
        let ranked = summary("ranked", updated: 900)
        let fresh = summary("fresh", updated: 1)
        harness.model.summaries = [ranked, fresh]
        harness.model.sessionOrder = [ranked.id.uuidString]
        // Unranked wins regardless of how stale it is, so a new session surfaces.
        #expect(harness.model.looseSessions.map(\.title) == ["fresh", "ranked"])
    }
}

// MARK: - Grouping

@Test func sessionsLandInTheirFolder() async throws {
    try await withWorkspace { harness in
        harness.model.folders = [.init(id: "f1", name: "API"),
                                 .init(id: "f2", name: "Web")]
        let inside = summary("inside")
        let outside = summary("outside")
        harness.model.summaries = [inside, outside]
        harness.model.membership = [inside.id.uuidString: "f1"]

        #expect(harness.model.folderGroups.map(\.name) == ["API", "Web"])
        #expect(harness.model.folderGroups.map { $0.sessions.map(\.title) }
                == [["inside"], []])
        #expect(harness.model.looseSessions.map(\.title) == ["outside"])
    }
}

@Test func aSessionPointingAtADeletedFolderBecomesLoose() async throws {
    try await withWorkspace { harness in
        let orphan = summary("orphan")
        harness.model.folders = [.init(id: "f1", name: "API")]
        harness.model.summaries = [orphan]
        harness.model.membership = [orphan.id.uuidString: "gone"]

        #expect(harness.model.folderGroups.map { $0.sessions.count } == [0])
        #expect(harness.model.looseSessions.map(\.title) == ["orphan"])
    }
}

// MARK: - Search

@Test func searchMatchesTitleOrWorkingDirectory() async throws {
    try await withWorkspace { harness in
        harness.model.summaries = [summary("deploy notes", in: "/code/web"),
                                   summary("unrelated", in: "/code/api")]

        harness.model.search = "DEPLOY"
        #expect(harness.model.looseSessions.map(\.title) == ["deploy notes"])

        harness.model.search = "api"
        #expect(harness.model.looseSessions.map(\.title) == ["unrelated"])
    }
}

@Test func searchKeepsAFolderWhoseOwnNameMatches() async throws {
    try await withWorkspace { harness in
        harness.model.folders = [.init(id: "f1", name: "Backend")]
        harness.model.summaries = []
        harness.model.search = "back"
        #expect(harness.model.folderGroups.map(\.name) == ["Backend"])
    }
}

@Test func searchHidesAnEmptyFolderThatDoesNotMatch() async throws {
    try await withWorkspace { harness in
        harness.model.folders = [.init(id: "f1", name: "Backend")]
        harness.model.summaries = []
        harness.model.search = "frontend"
        #expect(harness.model.folderGroups.isEmpty)
    }
}

// MARK: - Folder operations

@Test func renameFolderTrimsAndIgnoresBlankNames() async throws {
    try await withWorkspace { harness in
        harness.model.folders = [.init(id: "f1", name: "Original")]

        harness.model.renameFolder("f1", to: "   ")
        #expect(harness.model.folders.map(\.name) == ["Original"])

        harness.model.renameFolder("f1", to: "  Renamed  ")
        #expect(harness.model.folders.map(\.name) == ["Renamed"])

        harness.model.renameFolder("missing", to: "Nothing")
        #expect(harness.model.folders.map(\.name) == ["Renamed"])
    }
}

@Test func removeFolderAlsoClearsItsMembership() async throws {
    try await withWorkspace { harness in
        harness.model.folders = [.init(id: "f1", name: "API"),
                                 .init(id: "f2", name: "Web")]
        harness.model.membership = ["a": "f1", "b": "f2"]

        harness.model.removeFolder("f1")
        #expect(harness.model.folders.map(\.id) == ["f2"])
        #expect(harness.model.membership == ["b": "f2"])
    }
}

@Test func moveFolderInsertsBeforeTheTarget() async throws {
    try await withWorkspace { harness in
        harness.model.folders = [.init(id: "a", name: "A"),
                                 .init(id: "b", name: "B"),
                                 .init(id: "c", name: "C")]

        harness.model.moveFolder("c", before: "a")
        #expect(harness.model.folders.map(\.id) == ["c", "a", "b"])
    }
}

@Test func moveFolderAppendsWhenTheTargetIsNil() async throws {
    try await withWorkspace { harness in
        harness.model.folders = [.init(id: "a", name: "A"), .init(id: "b", name: "B")]

        harness.model.moveFolder("a", before: nil)
        #expect(harness.model.folders.map(\.id) == ["b", "a"])
    }
}

@Test func moveFolderIgnoresAMoveOntoItself() async throws {
    try await withWorkspace { harness in
        harness.model.folders = [.init(id: "a", name: "A"), .init(id: "b", name: "B")]

        harness.model.moveFolder("a", before: "a")
        #expect(harness.model.folders.map(\.id) == ["a", "b"])
    }
}

@Test func addFolderAppendsAFreshOne() async throws {
    try await withWorkspace { harness in
        harness.model.addFolder()
        harness.model.addFolder()
        #expect(harness.model.folders.count == 2)
        #expect(Set(harness.model.folders.map(\.id)).count == 2)
    }
}

// MARK: - Placing sessions

@Test func placeSessionAdoptsTheTargetFolder() async throws {
    try await withWorkspace { harness in
        let moving = summary("moving")
        let target = summary("target")
        harness.model.folders = [.init(id: "f1", name: "API")]
        harness.model.summaries = [moving, target]
        harness.model.membership = [target.id.uuidString: "f1"]

        harness.model.placeSession(moving.id, near: target.id)

        #expect(harness.model.membership[moving.id.uuidString] == "f1")
        #expect(harness.model.sessionOrder.first == moving.id.uuidString)
    }
}

@Test func placeSessionIgnoresAMoveOntoItself() async throws {
    try await withWorkspace { harness in
        let only = summary("only")
        harness.model.summaries = [only]

        harness.model.placeSession(only.id, near: only.id)
        #expect(harness.model.sessionOrder.isEmpty)
    }
}

@Test func moveSessionRecordsTheFolder() async throws {
    try await withWorkspace { harness in
        let session = UUID()
        harness.model.moveSession(session, toFolder: "f1")
        #expect(harness.model.membership[session.uuidString] == "f1")

        harness.model.moveSession(session, toFolder: nil)
        #expect(harness.model.membership[session.uuidString] == nil)
    }
}

// MARK: - Sessions backed by the store

@Test func selectRestoresAChatWithoutBringingItToLife() async throws {
    try await withWorkspace { harness in
        let session = storedSession("restored")
        try await harness.store.saveMetadata(session)
        await harness.model.refresh()

        await harness.model.select(session.id)

        #expect(harness.model.selectedID == session.id)
        #expect(harness.model.active?.title == "restored")
        #expect(harness.model.isLive(session.id) == false)
    }
}

@Test func indicatorRanksRateLimitAboveTheRest() async throws {
    try await withWorkspace { harness in
        let session = storedSession("busy")
        try await harness.store.saveMetadata(session)
        await harness.model.select(session.id)
        let chat = try #require(harness.model.active)

        #expect(harness.model.indicator(for: session.id) == nil)

        chat.hasUnread = true
        #expect(harness.model.indicator(for: session.id) == .unread)

        chat.isBusy = true
        #expect(harness.model.indicator(for: session.id) == .working)

        chat.pendingQuestion = nil
        chat.pending = PermissionRequest(id: "p1", toolName: "Bash",
                                         input: .object([:]), options: [])
        #expect(harness.model.indicator(for: session.id) == .waiting)

        chat.isRateLimited = true
        #expect(harness.model.indicator(for: session.id) == .rateLimited)
    }
}

@Test func indicatorIsQuietForASessionNeverOpened() async throws {
    try await withWorkspace { harness in
        #expect(harness.model.indicator(for: UUID()) == nil)
        #expect(harness.model.isLive(UUID()) == false)
    }
}

@Test func renameSessionTrimsAndPersists() async throws {
    try await withWorkspace { harness in
        let session = storedSession("before")
        try await harness.store.saveMetadata(session)
        await harness.model.refresh()

        await harness.model.renameSession(session.id, to: "   ")
        #expect(harness.model.summaries.map(\.title) == ["before"])

        await harness.model.renameSession(session.id, to: "  after  ")
        #expect(harness.model.summaries.map(\.title) == ["after"])
    }
}

@Test func deleteSessionClearsEveryTraceOfIt() async throws {
    try await withWorkspace { harness in
        let session = storedSession("doomed")
        try await harness.store.saveMetadata(session)
        await harness.model.refresh()

        harness.model.membership[session.id.uuidString] = "f1"
        harness.model.sessionOrder = [session.id.uuidString, "other"]
        harness.model.selectedID = session.id

        await harness.model.deleteSession(session.id)

        #expect(harness.model.summaries.isEmpty)
        #expect(harness.model.membership[session.id.uuidString] == nil)
        #expect(harness.model.sessionOrder == ["other"])
        #expect(harness.model.selectedID == nil)
    }
}

// MARK: - Default harness

@Test func theDefaultHarnessRoundTripsThroughTheInjectedDefaults() async throws {
    try await withWorkspace { harness in
        #expect(harness.model.defaultHarness == HarnessRegistry.standard.fallback)

        let target = try #require(harness.model.availableHarnesses.last)
        harness.model.defaultHarness = target
        #expect(harness.model.defaultHarness == target)

        let reopened = harness.reopened()
        #expect(reopened.defaultHarness == target)
    }
}

@Test func anUnknownStoredHarnessFallsBack() async throws {
    try await withWorkspace(seed: { defaults in
        defaults.set("ghost-harness", forKey: "Den.defaultHarness")
    }) { harness in
        #expect(harness.model.defaultHarness == HarnessRegistry.standard.fallback)
    }
}
