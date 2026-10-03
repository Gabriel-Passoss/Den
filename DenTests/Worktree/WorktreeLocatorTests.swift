import Testing
import Foundation
@testable import Den

private struct Fixture {
    let scratch: URL
    let repo: TestRepository
    let folder: URL
    var record: TaskWorktree

    var admin: URL { repo.checkout.appending(path: ".git/worktrees/feat-login") }
}

private func makeFixture(subpath: String? = nil, recordsGitDirectory: Bool = true) async throws -> Fixture {
    let scratch = try makeTree(["Área de trabalho"]).appending(path: "Área de trabalho")
        .resolvingSymlinksInPath()
    let repo = try await makeRepository(at: scratch.appending(path: "api"), scratch: scratch)
    let folder = scratch.appending(path: "worktrees/api/feat-login")
    try await runGit(["worktree", "add", "-q", "--no-track", "-b", "feat/login", folder.path, "origin/main"],
                     in: repo.checkout)
    let session = subpath.map { folder.appending(path: $0) } ?? folder
    let record = TaskWorktree(
        branch: "feat/login", sessionDirectory: session, mirrorRoot: nil,
        repos: [TaskWorktree.Repo(
            name: "api", original: repo.checkout, worktree: folder, base: "origin/main", remote: nil,
            gitDirectory: recordsGitDirectory
                ? repo.checkout.appending(path: ".git/worktrees/feat-login") : nil)])
    return Fixture(scratch: scratch, repo: repo, folder: folder, record: record)
}

private func resolved(_ url: URL?) -> String? { url?.resolvingSymlinksInPath().path }

private func remove(_ task: Fixture) {
    try? FileManager.default.removeItem(at: task.scratch.deletingLastPathComponent())
}

@Test func anUntouchedWorktreeComesBackAsRecorded() async throws {
    let task = try await makeFixture()
    defer { remove(task) }

    #expect(WorktreeLocator.current(task.record) == task.record)
}

@Test func aRenamedBranchIsFollowed() async throws {
    let task = try await makeFixture()
    defer { remove(task) }
    try await runGit(["branch", "-m", "feat/login", "feat/sign-in"], in: task.repo.checkout)

    let current = WorktreeLocator.current(task.record)

    #expect(current.branch == "feat/sign-in")
    #expect(current.repos.map { resolved($0.worktree) } == [resolved(task.folder)])
    #expect(resolved(current.sessionDirectory) == resolved(task.folder))
}

@Test func aMovedFolderIsFollowedWithTheSessionInsideIt() async throws {
    let task = try await makeFixture(subpath: "apps/web")
    defer { remove(task) }
    let moved = task.scratch.appending(path: "worktrees/api/feat-sign-in")
    try await runGit(["branch", "-m", "feat/login", "feat/sign-in"], in: task.repo.checkout)
    try await runGit(["worktree", "move", task.folder.path, moved.path], in: task.repo.checkout)

    let current = WorktreeLocator.current(task.record)

    #expect(current.branch == "feat/sign-in")
    #expect(current.repos.map { resolved($0.worktree) } == [resolved(moved)])
    #expect(resolved(current.sessionDirectory) == resolved(moved.appending(path: "apps/web")))
    #expect(resolved(current.repos.first?.gitDirectory) == resolved(task.admin))
}

@Test func aRecordWithoutItsGitDirectoryLearnsItWhileTheFolderIsStillThere() async throws {
    let task = try await makeFixture(recordsGitDirectory: false)
    defer { remove(task) }

    let current = WorktreeLocator.current(task.record)

    #expect(resolved(current.repos.first?.gitDirectory) == resolved(task.admin))
    #expect(current.repos.map { resolved($0.worktree) } == [resolved(task.folder)])
    #expect(current.branch == "feat/login")
}

@Test func aRecordWithoutItsGitDirectoryIsStillFoundAfterTheMove() async throws {
    let task = try await makeFixture(recordsGitDirectory: false)
    defer { remove(task) }
    let moved = task.scratch.appending(path: "worktrees/api/feat-sign-in")
    try await runGit(["branch", "-m", "feat/login", "feat/sign-in"], in: task.repo.checkout)
    try await runGit(["worktree", "move", task.folder.path, moved.path], in: task.repo.checkout)

    let current = WorktreeLocator.current(task.record)

    #expect(current.branch == "feat/sign-in")
    #expect(current.repos.map { resolved($0.worktree) } == [resolved(moved)])
    #expect(resolved(current.sessionDirectory) == resolved(moved))
}

@Test func aDetachedHeadKeepsTheRecordedBranch() async throws {
    let task = try await makeFixture()
    defer { remove(task) }
    try await runGit(["checkout", "-q", "--detach"], in: task.folder)

    #expect(WorktreeLocator.current(task.record) == task.record)
}

@Test func aRemovedWorktreeLeavesTheRecordAlone() async throws {
    let task = try await makeFixture()
    defer { remove(task) }
    try await runGit(["worktree", "remove", "--force", task.folder.path], in: task.repo.checkout)

    #expect(WorktreeLocator.current(task.record) == task.record)
}

@Test func aMirrorKeepsItsSessionFolderWhenOneRepoMoves() async throws {
    var task = try await makeFixture()
    defer { remove(task) }
    let mirror = task.folder.deletingLastPathComponent()
    task.record.sessionDirectory = mirror
    task.record.mirrorRoot = mirror
    let moved = task.scratch.appending(path: "elsewhere/api")
    try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try await runGit(["worktree", "move", task.folder.path, moved.path], in: task.repo.checkout)

    let current = WorktreeLocator.current(task.record)

    #expect(current.repos.map { resolved($0.worktree) } == [resolved(moved)])
    #expect(current.sessionDirectory == mirror)
    #expect(current.mirrorRoot == mirror)
}

@Test func aSymlinkedSpellingOfTheSameFolderIsNotAMove() async throws {
    var task = try await makeFixture()
    defer { remove(task) }
    let alias = task.scratch.appending(path: "alias")
    try FileManager.default.createSymbolicLink(at: alias,
                                               withDestinationURL: task.scratch.appending(path: "worktrees"))
    let spelled = alias.appending(path: "api/feat-login")
    task.record.sessionDirectory = spelled
    task.record.repos[0].worktree = spelled

    #expect(WorktreeLocator.current(task.record) == task.record)
}
