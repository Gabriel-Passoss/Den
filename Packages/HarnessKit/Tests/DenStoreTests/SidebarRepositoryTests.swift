import Testing
import Foundation
import HarnessCore
import DenStore

private let backend = SidebarFolder(id: "f-backend", name: "Backend")
private let frontend = SidebarFolder(id: "f-frontend", name: "Frontend")

@Test func anEmptyStoreHasAnEmptyLayout() throws {
    #expect(try DenStore.inMemory().sidebar.load() == SidebarLayout())
}

@Test func foldersComeBackInTheOrderTheyWereSaved() throws {
    let sidebar = try DenStore.inMemory().sidebar

    try sidebar.save(SidebarLayout(folders: [backend, frontend]))
    #expect(try sidebar.load().folders == [backend, frontend])

    let renamed = SidebarFolder(id: backend.id, name: "it's \"API\" 🧱")
    try sidebar.save(SidebarLayout(folders: [frontend, renamed]))
    #expect(try sidebar.load().folders == [frontend, renamed])

    try sidebar.save(SidebarLayout(folders: [renamed]))
    #expect(try sidebar.load().folders == [renamed])
}

@Test func membershipAndOrderRoundTrip() async throws {
    let store = try DenStore.inMemory()
    let first = try await saved(in: store).id
    let second = try await saved(in: store).id
    let third = try await saved(in: store).id
    let layout = SidebarLayout(folders: [backend, frontend],
                               membership: [first: backend.id, third: frontend.id],
                               order: [third, first, second])

    try store.sidebar.save(layout)

    #expect(try store.sidebar.load() == layout)
}

@Test func referencesToUnknownSessionsOrFoldersAreDropped() async throws {
    let store = try DenStore.inMemory()
    let known = try await saved(in: store).id
    let ghost = UUID()

    try store.sidebar.save(SidebarLayout(folders: [backend],
                                         membership: [known: "f-gone", ghost: backend.id],
                                         order: [ghost, known]))

    #expect(try store.sidebar.load() == SidebarLayout(folders: [backend], order: [known]))
}

@Test func aSessionLeftOutOfTheLayoutLosesItsPlace() async throws {
    let store = try DenStore.inMemory()
    let session = try await saved(in: store).id
    try store.sidebar.save(SidebarLayout(folders: [backend], membership: [session: backend.id],
                                         order: [session]))

    try store.sidebar.save(SidebarLayout(folders: [backend]))

    #expect(try store.sidebar.load() == SidebarLayout(folders: [backend]))
}

@Test func removingAFolderLoosensItsSessions() async throws {
    let store = try DenStore.inMemory()
    let session = try await saved(in: store).id
    try store.sidebar.save(SidebarLayout(folders: [backend, frontend],
                                         membership: [session: backend.id], order: [session]))

    try store.sidebar.save(SidebarLayout(folders: [frontend], membership: [session: backend.id],
                                         order: [session]))

    #expect(try store.sidebar.load() == SidebarLayout(folders: [frontend], order: [session]))
}

@Test func deletingASessionTakesItOutOfTheLayout() async throws {
    let store = try DenStore.inMemory()
    let doomed = try await saved(in: store).id
    let kept = try await saved(in: store).id
    try store.sidebar.save(SidebarLayout(folders: [backend],
                                         membership: [doomed: backend.id, kept: backend.id],
                                         order: [doomed, kept]))

    try await store.sessions.delete(doomed)

    #expect(try store.sidebar.load() == SidebarLayout(folders: [backend], membership: [kept: backend.id],
                                                      order: [kept]))
}

@Test func savingASessionsMetadataLeavesItsPlaceAlone() async throws {
    let store = try DenStore.inMemory()
    var session = try await saved(in: store)
    let layout = SidebarLayout(folders: [backend], membership: [session.id: backend.id], order: [session.id])
    try store.sidebar.save(layout)

    session.title = "renomeada"
    try await store.sessions.saveMetadata(session)

    #expect(try store.sidebar.load() == layout)
}
