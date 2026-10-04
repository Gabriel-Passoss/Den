import Testing
import Foundation
import HarnessCore
import DenStore
@testable import Den

private struct Shelf {
    let repositories = scratchRepositories()
    let id: UUID

    init() async throws {
        let session = storedSession("tarefa")
        try await repositories.sessions.saveMetadata(session)
        id = session.id
    }

    var ledger: TaskLedger { TaskLedger(repository: repositories.taskWorktrees) }
}

func sampleWorktree(branch: String = "den/NS-1-fix") -> TaskWorktree {
    let worktree = URL(fileURLWithPath: "/wt/api/NS-1-fix")
    return TaskWorktree(
        branch: branch, sessionDirectory: worktree.appending(path: "apps/web"), mirrorRoot: nil,
        repos: [TaskWorktree.Repo(name: "api", original: URL(fileURLWithPath: "/code/api"),
                                  worktree: worktree, base: "origin/main",
                                  remote: GitHubRemote(host: "github.com", owner: "den", name: "api"))])
}

@Test func theLedgerWritesThroughAndForgets() async throws {
    let shelf = try await Shelf()
    let ledger = shelf.ledger

    ledger.record(sampleWorktree(), for: shelf.id)
    #expect(shelf.ledger.worktree(for: shelf.id) == sampleWorktree())

    ledger.forget(shelf.id)
    #expect(shelf.ledger.worktree(for: shelf.id) == nil)
}

@Test func aWorktreeNamesItsFolderAndLocation() {
    let single = sampleWorktree()
    #expect(single.folderName == "NS-1-fix")
    #expect(single.displayLocation == "/wt/api/NS-1-fix")

    var mirrored = single
    mirrored.mirrorRoot = URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".den/worktrees/scalemed/x")
    #expect(mirrored.folderName == "x")
    #expect(mirrored.displayLocation == "~/.den/worktrees/scalemed/x")
}

@Test func anEntryFromTheFirstDeliveryStillDecodes() throws {
    let json = """
        {"worktree": {"branch": "den/x", "sessionDirectory": "file:///wt/api/x", "repos": []}}
        """
    let entry = try JSONDecoder().decode(TaskWorktreeEntry.self, from: Data(json.utf8))

    #expect(entry.worktree.branch == "den/x")
    #expect(entry.pullRequests.isEmpty)
    #expect(entry.dismissed.isEmpty)
}

@Test func theLedgerKeepsPullRequestsAndDismissals() async throws {
    let shelf = try await Shelf()
    let path = "/wt/api/NS-1-fix"
    let ledger = shelf.ledger
    ledger.record(sampleWorktree(), for: shelf.id)

    ledger.setPullRequest(makePullRequest(number: 80), for: shelf.id, worktree: path)
    ledger.dismiss(shelf.id, worktree: path, signature: "open|false|none|none|mergeable")

    let reopened = shelf.ledger
    #expect(reopened.pullRequests(for: shelf.id)[path]?.number == 80)
    #expect(reopened.dismissedSignature(for: shelf.id, worktree: path) == "open|false|none|none|mergeable")

    ledger.setPullRequest(nil, for: shelf.id, worktree: path)
    #expect(shelf.ledger.pullRequests(for: shelf.id).isEmpty)
}

@Test func aMovedWorktreeKeepsItsPullRequestAndDismissalUnderTheNewPath() async throws {
    let shelf = try await Shelf()
    let ledger = shelf.ledger
    ledger.record(sampleWorktree(), for: shelf.id)
    ledger.setPullRequest(makePullRequest(number: 80), for: shelf.id, worktree: "/wt/api/NS-1-fix")
    ledger.dismiss(shelf.id, worktree: "/wt/api/NS-1-fix", signature: "open")
    var moved = sampleWorktree(branch: "fix/NS-1-login")
    moved.repos[0].worktree = URL(fileURLWithPath: "/wt/api/fix-NS-1-login")
    moved.sessionDirectory = URL(fileURLWithPath: "/wt/api/fix-NS-1-login/apps/web")

    ledger.update(moved, for: shelf.id)

    let reopened = shelf.ledger
    #expect(reopened.worktree(for: shelf.id) == moved)
    #expect(reopened.pullRequests(for: shelf.id).mapValues(\.number) == ["/wt/api/fix-NS-1-login": 80])
    #expect(reopened.dismissedSignature(for: shelf.id, worktree: "/wt/api/fix-NS-1-login") == "open")
    #expect(reopened.dismissedSignature(for: shelf.id, worktree: "/wt/api/NS-1-fix") == nil)
}

@Test func aRecordForAnUnknownSessionIsNeverInvented() async throws {
    let shelf = try await Shelf()
    let ledger = shelf.ledger

    ledger.update(sampleWorktree(), for: UUID())
    ledger.setPullRequest(makePullRequest(), for: UUID(), worktree: "/wt/x")

    #expect(ledger.entries.isEmpty)
}

@Test func aLedgerOverAnEmptyStoreStartsEmpty() async throws {
    #expect(try await Shelf().ledger.entries.isEmpty)
}

@Test func deletingTheSessionForgetsItsWorktree() async throws {
    let shelf = try await Shelf()
    shelf.ledger.record(sampleWorktree(), for: shelf.id)

    try await shelf.repositories.sessions.delete(shelf.id)

    #expect(shelf.ledger.worktree(for: shelf.id) == nil)
}

@Test func aWorktreeForASessionTheStoreDoesNotKnowLivesOnlyInMemory() async throws {
    let shelf = try await Shelf()
    let ledger = shelf.ledger
    let stranger = UUID()

    ledger.record(sampleWorktree(), for: stranger)

    #expect(ledger.worktree(for: stranger) == sampleWorktree())
    #expect(shelf.ledger.worktree(for: stranger) == nil)
}
