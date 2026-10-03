import Testing
import Foundation
@testable import Den

private func scratchFolder() throws -> URL {
    try makeTree(["Área de trabalho"]).appending(path: "Área de trabalho")
}

private func singlePlan(_ checkout: URL, branch: String, root: URL) -> WorktreePlan {
    WorktreePlanner.plan(layout: .single(RepoCandidate(toplevel: checkout)),
                         sessionDirectory: checkout, chosen: [], branch: branch,
                         prefix: "den/", root: root, entries: [])
}

private func severalPlan(_ folder: URL, branch: String, root: URL) throws -> WorktreePlan {
    let layout = try #require(WorktreeLayout.detect(folder))
    let entries = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
    return WorktreePlanner.plan(layout: layout, sessionDirectory: folder,
                                chosen: Set(layout.repos.map(\.id)), branch: branch,
                                prefix: "den/", root: root, entries: entries)
}

@Test func aWorktreeStartsFromTheFreshDefaultBranchWithoutUpstream() async throws {
    let scratch = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: scratch.deletingLastPathComponent()) }
    let repo = try await makeRepository(at: scratch.appending(path: "api"), scratch: scratch)
    try await runGit(["commit", "-q", "--allow-empty", "-m", "newer"], in: repo.seed)
    try await runGit(["push", "-q", repo.origin.path, "main"], in: repo.seed)
    let newest = try await runGit(["rev-parse", "HEAD"], in: repo.seed)

    let made = try await WorktreeMaker().make(
        singlePlan(repo.checkout, branch: "den/task", root: scratch.appending(path: "worktrees")))

    let worktree = scratch.appending(path: "worktrees/api/task")
    #expect(made.worktree.repos.map(\.worktree.path) == [worktree.path])
    #expect(made.worktree.repos.first?.base == "origin/main")
    #expect(made.worktree.repos.first?.remote == nil)
    #expect(made.warnings.isEmpty)
    #expect(try await runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: worktree) == "den/task")
    #expect(try await runGit(["rev-parse", "HEAD"], in: worktree) == newest)
    #expect(!(await gitSucceeds(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"],
                                in: worktree)))
}

@Test func masterIsFoundThroughOriginHead() async throws {
    let scratch = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: scratch.deletingLastPathComponent()) }
    let repo = try await makeRepository(at: scratch.appending(path: "api"), scratch: scratch,
                                        defaultBranch: "master")

    let made = try await WorktreeMaker().make(
        singlePlan(repo.checkout, branch: "den/task", root: scratch.appending(path: "worktrees")))

    #expect(made.worktree.repos.first?.base == "origin/master")
}

@Test func aRepoWithoutRemoteStartsFromItsLocalDefaultBranch() async throws {
    let scratch = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: scratch.deletingLastPathComponent()) }
    let checkout = scratch.appending(path: "solo")
    try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
    try await runGit(["init", "-q", "-b", "main"], in: checkout)
    try await runGit(["commit", "-q", "--allow-empty", "-m", "initial"], in: checkout)

    let made = try await WorktreeMaker().make(
        singlePlan(checkout, branch: "den/task", root: scratch.appending(path: "worktrees")))

    #expect(made.worktree.repos.first?.base == "main")
    #expect(made.warnings.isEmpty)
}

@Test func anUnreachableRemoteFallsBackToTheKnownBranchWithAWarning() async throws {
    let scratch = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: scratch.deletingLastPathComponent()) }
    let repo = try await makeRepository(at: scratch.appending(path: "api"), scratch: scratch)
    try await runGit(["remote", "set-url", "origin", scratch.appending(path: "missing.git").path],
                     in: repo.checkout)

    let made = try await WorktreeMaker().make(
        singlePlan(repo.checkout, branch: "den/task", root: scratch.appending(path: "worktrees")))

    #expect(made.worktree.repos.first?.base == "origin/main")
    #expect(made.warnings.first?.hasPrefix("Sem rede: api partiu de origin/main") == true)
}

@Test func aHungFetchGivesUpAtTheDeadline() async throws {
    let scratch = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: scratch.deletingLastPathComponent()) }
    let repo = try await makeRepository(at: scratch.appending(path: "api"), scratch: scratch)
    var maker = WorktreeMaker()
    maker.fetchTimeout = .milliseconds(200)
    maker.git = { arguments, directory, timeout in
        if arguments.first == "fetch" {
            return await TimedProcess.run("/bin/sleep", ["30"], timeout: timeout)
        }
        return await WorktreeMaker.systemGit(arguments, directory, timeout)
    }

    let made = try await maker.make(
        singlePlan(repo.checkout, branch: "den/task", root: scratch.appending(path: "worktrees")))

    #expect(made.warnings.first?.hasPrefix("Sem rede: api") == true)
}

@Test func severalReposAreMirroredAndTheLooseFilesLinked() async throws {
    let scratch = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: scratch.deletingLastPathComponent()) }
    let folder = scratch.appending(path: "scalemed")
    try await makeRepository(at: folder.appending(path: "backend"), scratch: scratch)
    try await makeRepository(at: folder.appending(path: "apps/frontend"), scratch: scratch)
    try "regras\n".write(to: folder.appending(path: "CLAUDE.md"), atomically: true, encoding: .utf8)

    let recorder = ProgressRecorder()
    let made = try await WorktreeMaker().make(
        try severalPlan(folder, branch: "den/NS-1-fix", root: scratch.appending(path: "worktrees")),
        progress: { await recorder.add($0) })
    let progress = await recorder.steps

    let mirror = scratch.appending(path: "worktrees/scalemed/NS-1-fix")
    #expect(made.worktree.mirrorRoot?.path == mirror.path)
    #expect(made.worktree.sessionDirectory.path == mirror.path)
    #expect(try await runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: mirror.appending(path: "backend"))
            == "den/NS-1-fix")
    #expect(try await runGit(["rev-parse", "--abbrev-ref", "HEAD"],
                             in: mirror.appending(path: "apps/frontend")) == "den/NS-1-fix")
    let link = try FileManager.default.destinationOfSymbolicLink(
        atPath: mirror.appending(path: "CLAUDE.md").path)
    #expect(URL(fileURLWithPath: link).resolvingSymlinksInPath().path
            == folder.appending(path: "CLAUDE.md").resolvingSymlinksInPath().path)
    #expect(progress.contains(.creating("backend")))
    #expect(progress.last == .linking)
}

private actor ProgressRecorder {
    private(set) var steps: [WorktreeMaker.Progress] = []
    func add(_ step: WorktreeMaker.Progress) { steps.append(step) }
}

@Test func aFailureInOneRepoUndoesTheOthers() async throws {
    let scratch = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: scratch.deletingLastPathComponent()) }
    let folder = scratch.appending(path: "scalemed")
    try await makeRepository(at: folder.appending(path: "backend"), scratch: scratch)
    try await makeRepository(at: folder.appending(path: "frontend"), scratch: scratch)
    try await runGit(["branch", "den/task"], in: folder.appending(path: "frontend"))

    do {
        _ = try await WorktreeMaker().make(
            try severalPlan(folder, branch: "den/task", root: scratch.appending(path: "worktrees")))
        Issue.record("the creation should have failed")
    } catch let failure as WorktreeMaker.Failure {
        #expect(failure.repo == "frontend")
    }

    #expect(!FileManager.default.fileExists(atPath: scratch.appending(path: "worktrees/scalemed/task").path))
    #expect(!(await gitSucceeds(["show-ref", "--verify", "--quiet", "refs/heads/den/task"],
                                in: folder.appending(path: "backend"))))
    #expect(await gitSucceeds(["show-ref", "--verify", "--quiet", "refs/heads/den/task"],
                              in: folder.appending(path: "frontend")))
}

@Test func takenNamesListLocalAndRemoteBranches() async throws {
    let scratch = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: scratch.deletingLastPathComponent()) }
    let repo = try await makeRepository(at: scratch.appending(path: "api"), scratch: scratch)
    try await runGit(["branch", "feature/x"], in: repo.checkout)
    try await runGit(["push", "-q", repo.origin.path, "main:shared"], in: repo.seed)
    try await runGit(["fetch", "-q", "origin"], in: repo.checkout)

    let taken = await WorktreeMaker().takenNames(in: [repo.checkout])

    let names = try #require(taken[repo.checkout])
    #expect(names.isSuperset(of: ["main", "feature/x", "shared"]))
    #expect(!names.contains("HEAD"))
}

@Test func branchNamesAreValidatedByGit() async throws {
    let scratch = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: scratch.deletingLastPathComponent()) }
    let repo = try await makeRepository(at: scratch.appending(path: "api"), scratch: scratch)
    let maker = WorktreeMaker()

    #expect(await maker.isValidBranchName("den/ok", in: repo.checkout))
    #expect(!(await maker.isValidBranchName("den/a..b", in: repo.checkout)))
    #expect(!(await maker.isValidBranchName("den/com espaço", in: repo.checkout)))
}

@Test func anExistingMirrorIsNeverTouched() async throws {
    let scratch = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: scratch.deletingLastPathComponent()) }
    let folder = scratch.appending(path: "scalemed")
    try await makeRepository(at: folder.appending(path: "backend"), scratch: scratch)
    let mirror = scratch.appending(path: "worktrees/scalemed/task")
    try FileManager.default.createDirectory(at: mirror, withIntermediateDirectories: true)
    try "trabalho em andamento\n".write(to: mirror.appending(path: "notes.md"), atomically: true, encoding: .utf8)

    await #expect(throws: WorktreeMaker.Failure.self) {
        try await WorktreeMaker().make(
            try severalPlan(folder, branch: "den/task", root: scratch.appending(path: "worktrees")))
    }

    #expect(FileManager.default.fileExists(atPath: mirror.appending(path: "notes.md").path))
    #expect(!(await gitSucceeds(["show-ref", "--verify", "--quiet", "refs/heads/den/task"],
                                in: folder.appending(path: "backend"))))
}

@Test func aDotDotFolderIsRefusedBeforeAnythingHappens() async throws {
    let scratch = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: scratch.deletingLastPathComponent()) }
    let folder = scratch.appending(path: "scalemed")
    try await makeRepository(at: folder.appending(path: "backend"), scratch: scratch)
    let root = scratch.appending(path: "worktrees")
    let keep = root.appending(path: "scalemed/other/keep.md")
    try FileManager.default.createDirectory(at: keep.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "keep\n".write(to: keep, atomically: true, encoding: .utf8)

    await #expect(throws: WorktreeMaker.Failure.self) {
        try await WorktreeMaker().make(try severalPlan(folder, branch: "den/..", root: root))
    }

    #expect(FileManager.default.fileExists(atPath: keep.path))
}
