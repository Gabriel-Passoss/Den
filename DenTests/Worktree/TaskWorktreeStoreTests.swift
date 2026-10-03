import Testing
import Foundation
@testable import Den

private func temporaryFile() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "DenTests-" + UUID().uuidString)
        .appending(path: "task-worktrees.json")
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
    let url = temporaryFile()
    let folder = url.deletingLastPathComponent()
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("{nope".utf8).write(to: url)

    #expect(TaskWorktreeStore(url: url).load().isEmpty)
    let siblings = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    #expect(siblings.contains { $0.hasPrefix("task-worktrees.corrupt-") })
}

@Test func theLedgerWritesThroughAndForgets() throws {
    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let id = UUID()
    let ledger = TaskLedger(store: TaskWorktreeStore(url: url))

    ledger.record(sampleWorktree(), for: id)
    #expect(TaskLedger(store: TaskWorktreeStore(url: url)).worktree(for: id) == sampleWorktree())

    ledger.forget(id)
    #expect(TaskLedger(store: TaskWorktreeStore(url: url)).worktree(for: id) == nil)
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
    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let id = UUID()
    let json = """
        {"version": 1, "sessions": {"\(id.uuidString)": {"worktree": {"branch": "den/x",
         "sessionDirectory": "file:///wt/api/x", "repos": []}}}}
        """
    try Data(json.utf8).write(to: url)

    let entry = try #require(TaskWorktreeStore(url: url).load()[id])

    #expect(entry.worktree.branch == "den/x")
    #expect(entry.pullRequests.isEmpty)
    #expect(entry.dismissed.isEmpty)
}

@Test func theLedgerKeepsPullRequestsAndDismissals() throws {
    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let id = UUID()
    let path = "/wt/api/NS-1-fix"
    let ledger = TaskLedger(store: TaskWorktreeStore(url: url))
    ledger.record(sampleWorktree(), for: id)

    ledger.setPullRequest(makePullRequest(number: 80), for: id, worktree: path)
    ledger.dismiss(id, worktree: path, signature: "open|false|none|none|mergeable")

    let reopened = TaskLedger(store: TaskWorktreeStore(url: url))
    #expect(reopened.pullRequests(for: id)[path]?.number == 80)
    #expect(reopened.dismissedSignature(for: id, worktree: path) == "open|false|none|none|mergeable")

    ledger.setPullRequest(nil, for: id, worktree: path)
    #expect(TaskLedger(store: TaskWorktreeStore(url: url)).pullRequests(for: id).isEmpty)
}

@Test func aMovedWorktreeKeepsItsPullRequestAndDismissalUnderTheNewPath() throws {
    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let id = UUID()
    let ledger = TaskLedger(store: TaskWorktreeStore(url: url))
    ledger.record(sampleWorktree(), for: id)
    ledger.setPullRequest(makePullRequest(number: 80), for: id, worktree: "/wt/api/NS-1-fix")
    ledger.dismiss(id, worktree: "/wt/api/NS-1-fix", signature: "open")
    var moved = sampleWorktree(branch: "fix/NS-1-login")
    moved.repos[0].worktree = URL(fileURLWithPath: "/wt/api/fix-NS-1-login")
    moved.sessionDirectory = URL(fileURLWithPath: "/wt/api/fix-NS-1-login/apps/web")

    ledger.update(moved, for: id)

    let reopened = TaskLedger(store: TaskWorktreeStore(url: url))
    #expect(reopened.worktree(for: id) == moved)
    #expect(reopened.pullRequests(for: id).mapValues(\.number) == ["/wt/api/fix-NS-1-login": 80])
    #expect(reopened.dismissedSignature(for: id, worktree: "/wt/api/fix-NS-1-login") == "open")
    #expect(reopened.dismissedSignature(for: id, worktree: "/wt/api/NS-1-fix") == nil)
}

@Test func updatingAnUnknownSessionRecordsNothing() throws {
    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let ledger = TaskLedger(store: TaskWorktreeStore(url: url))

    ledger.update(sampleWorktree(), for: UUID())

    #expect(ledger.entries.isEmpty)
}

@Test func aPullRequestForAnUnknownSessionIsIgnored() throws {
    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let ledger = TaskLedger(store: TaskWorktreeStore(url: url))

    ledger.setPullRequest(makePullRequest(), for: UUID(), worktree: "/wt/x")

    #expect(ledger.entries.isEmpty)
}
