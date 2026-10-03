import Testing
import Foundation
@testable import Den

private func temporaryFile() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "DenTests-" + UUID().uuidString)
        .appending(path: "task-worktrees.json")
}

private struct Shelf {
    let url = temporaryFile()
    let id = UUID()

    var ledger: TaskLedger { TaskLedger(store: TaskWorktreeStore(url: url)) }

    func write(_ text: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func remove() { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
}

func sampleWorktree(branch: String = "den/NS-1-fix") -> TaskWorktree {
    let worktree = URL(fileURLWithPath: "/wt/api/NS-1-fix")
    return TaskWorktree(
        branch: branch, sessionDirectory: worktree.appending(path: "apps/web"), mirrorRoot: nil,
        repos: [TaskWorktree.Repo(name: "api", original: URL(fileURLWithPath: "/code/api"),
                                  worktree: worktree, base: "origin/main",
                                  remote: GitHubRemote(host: "github.com", owner: "den", name: "api"))])
}

@Test func aMissingWorktreeFileLoadsAsEmpty() {
    #expect(TaskWorktreeStore(url: temporaryFile()).load().isEmpty)
}

@Test func savedWorktreesComeBackIntact() throws {
    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = TaskWorktreeStore(url: url)
    let id = UUID()

    try store.save([id: .init(worktree: sampleWorktree())])

    #expect(store.load() == [id: .init(worktree: sampleWorktree())])
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    #expect(object?["version"] as? Int == 1)
    #expect((object?["sessions"] as? [String: Any])?.keys.first == id.uuidString)
}

@Test func aCorruptWorktreeFileIsSetAside() throws {
    let shelf = Shelf()
    defer { shelf.remove() }
    try shelf.write("{nope")

    #expect(TaskWorktreeStore(url: shelf.url).load().isEmpty)
    let siblings = try FileManager.default.contentsOfDirectory(atPath: shelf.url.deletingLastPathComponent().path)
    #expect(siblings.contains { $0.hasPrefix("task-worktrees.corrupt-") })
}

@Test func theLedgerWritesThroughAndForgets() {
    let shelf = Shelf()
    defer { shelf.remove() }
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

@Test func aFileFromTheFirstDeliveryStillLoads() throws {
    let shelf = Shelf()
    defer { shelf.remove() }
    try shelf.write("""
        {"version": 1, "sessions": {"\(shelf.id.uuidString)": {"worktree": {"branch": "den/x",
         "sessionDirectory": "file:///wt/api/x", "repos": []}}}}
        """)

    let entry = try #require(TaskWorktreeStore(url: shelf.url).load()[shelf.id])

    #expect(entry.worktree.branch == "den/x")
    #expect(entry.pullRequests.isEmpty)
    #expect(entry.dismissed.isEmpty)
}

@Test func theLedgerKeepsPullRequestsAndDismissals() {
    let shelf = Shelf()
    defer { shelf.remove() }
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

@Test func aMovedWorktreeKeepsItsPullRequestAndDismissalUnderTheNewPath() {
    let shelf = Shelf()
    defer { shelf.remove() }
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

@Test func aRecordForAnUnknownSessionIsNeverInvented() {
    let shelf = Shelf()
    defer { shelf.remove() }
    let ledger = shelf.ledger

    ledger.update(sampleWorktree(), for: UUID())
    ledger.setPullRequest(makePullRequest(), for: UUID(), worktree: "/wt/x")

    #expect(ledger.entries.isEmpty)
}
