import Foundation
import Testing
@testable import Den

private struct Fixture {
    let scratch: URL
    let repo: TestRepository
    let folder: URL
    var record: TaskWorktree

    var admin: URL { repo.checkout.appending(path: ".git/worktrees/feat-login") }
    var moved: URL { scratch.appending(path: "worktrees/api/feat-sign-in") }
    var current: TaskWorktree { WorktreeLocator.current(record) }

    func rename() async throws {
        try await runGit(["branch", "-m", "feat/login", "feat/sign-in"], in: repo.checkout)
    }

    func move(to destination: URL) async throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try await runGit(["worktree", "move", folder.path, destination.path], in: repo.checkout)
    }

    func remove() {
        try? FileManager.default.removeItem(at: scratch.deletingLastPathComponent())
    }
}

private func makeFixture(subpath: String? = nil, recordsGitDirectory: Bool = true) async throws -> Fixture {
    let scratch = try makeTree(["Área de trabalho"]).appending(path: "Área de trabalho")
        .resolvingSymlinksInPath()
    let repo = try await makeRepository(at: scratch.appending(path: "api"), scratch: scratch)
    let folder = scratch.appending(path: "worktrees/api/feat-login")
    try await runGit(["worktree", "add", "-q", "--no-track", "-b", "feat/login", folder.path, "origin/main"],
                     in: repo.checkout)
    let admin = recordsGitDirectory ? repo.checkout.appending(path: ".git/worktrees/feat-login") : nil
    let record = TaskWorktree(
        branch: "feat/login", sessionDirectory: subpath.map { folder.appending(path: $0) } ?? folder,
        mirrorRoot: nil,
        repos: [TaskWorktree.Repo(name: "api", original: repo.checkout, worktree: folder,
                                  base: "origin/main", remote: nil, gitDirectory: admin)])
    return Fixture(scratch: scratch, repo: repo, folder: folder, record: record)
}

private func resolved(_ url: URL?) -> String? { url?.resolvingSymlinksInPath().path }

private func folders(of task: TaskWorktree) -> [String?] { task.repos.map { resolved($0.worktree) } }

@Test func anUntouchedWorktreeComesBackAsRecorded() async throws {
    let task = try await makeFixture()
    defer { task.remove() }

    #expect(task.current == task.record)
}

@Test func aRenamedBranchIsFollowed() async throws {
    let task = try await makeFixture()
    defer { task.remove() }
    try await task.rename()

    let current = task.current

    #expect(current.branch == "feat/sign-in")
    #expect(folders(of: current) == [resolved(task.folder)])
    #expect(resolved(current.sessionDirectory) == resolved(task.folder))
}

@Test func aMovedFolderIsFollowedWithTheSessionInsideIt() async throws {
    let task = try await makeFixture(subpath: "apps/web")
    defer { task.remove() }
    try await task.rename()
    try await task.move(to: task.moved)

    let current = task.current

    #expect(current.branch == "feat/sign-in")
    #expect(folders(of: current) == [resolved(task.moved)])
    #expect(resolved(current.sessionDirectory) == resolved(task.moved.appending(path: "apps/web")))
    #expect(resolved(current.repos.first?.gitDirectory) == resolved(task.admin))
}

@Test func aRecordWithoutItsGitDirectoryLearnsItWhileTheFolderIsStillThere() async throws {
    let task = try await makeFixture(recordsGitDirectory: false)
    defer { task.remove() }

    let current = task.current

    #expect(resolved(current.repos.first?.gitDirectory) == resolved(task.admin))
    #expect(folders(of: current) == [resolved(task.folder)])
    #expect(current.branch == "feat/login")
}

@Test func aRecordWithoutItsGitDirectoryIsStillFoundAfterTheMove() async throws {
    let task = try await makeFixture(recordsGitDirectory: false)
    defer { task.remove() }
    try await task.move(to: task.moved)

    let current = task.current

    #expect(folders(of: current) == [resolved(task.moved)])
    #expect(resolved(current.sessionDirectory) == resolved(task.moved))
}

@Test func aDetachedHeadKeepsTheRecordedBranch() async throws {
    let task = try await makeFixture()
    defer { task.remove() }
    try await runGit(["checkout", "-q", "--detach"], in: task.folder)

    #expect(task.current == task.record)
}

@Test func aRemovedWorktreeLeavesTheRecordAlone() async throws {
    let task = try await makeFixture()
    defer { task.remove() }
    try await runGit(["worktree", "remove", "--force", task.folder.path], in: task.repo.checkout)

    #expect(task.current == task.record)
}

@Test func aMirrorKeepsItsSessionFolderWhenOneRepoMoves() async throws {
    var task = try await makeFixture()
    defer { task.remove() }
    let mirror = task.folder.deletingLastPathComponent()
    task.record.sessionDirectory = mirror
    task.record.mirrorRoot = mirror
    let elsewhere = task.scratch.appending(path: "elsewhere/api")
    try await task.move(to: elsewhere)

    let current = task.current

    #expect(folders(of: current) == [resolved(elsewhere)])
    #expect(current.sessionDirectory == mirror)
    #expect(current.mirrorRoot == mirror)
}

@Test func aSymlinkedSpellingOfTheSameFolderIsNotAMove() async throws {
    var task = try await makeFixture()
    defer { task.remove() }
    let alias = task.scratch.appending(path: "alias")
    try FileManager.default.createSymbolicLink(at: alias,
                                               withDestinationURL: task.scratch.appending(path: "worktrees"))
    let spelled = alias.appending(path: "api/feat-login")
    task.record.sessionDirectory = spelled
    task.record.repos[0].worktree = spelled

    #expect(task.current == task.record)
}
