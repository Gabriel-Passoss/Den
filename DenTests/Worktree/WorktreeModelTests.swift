import Testing
import Foundation
import HarnessCore
@testable import Den

@MainActor
private struct Bench {
    let chat: ChatModel
    let harness: FakeHarness
    let worktrees: WorktreeModel
    let scratch: URL
    let checkout: URL
    let defaults: UserDefaults

    func chat(in directory: URL) -> ChatModel {
        ChatModel(store: FileTranscriptStore(root: scratch.appending(path: "sessions")),
                  workingDirectory: directory, harness: harness.id,
                  cache: SessionCache(defaults: defaults),
                  registry: HarnessRegistry(harnesses: [harness]),
                  attachmentsRoot: scratch.appending(path: "attachments"))
    }
}

@MainActor
private func withBench(maker: WorktreeMaker = WorktreeMaker(),
                       suggester: BranchSuggester = BranchSuggester(),
                       oneShot: [String]? = nil,
                       _ body: (Bench) async throws -> Void) async throws {
    let scratchDefaults = ScratchDefaults()
    let parent = try makeTree(["Área de trabalho/sessions"])
    defer {
        scratchDefaults.remove()
        try? FileManager.default.removeItem(at: parent)
    }
    let scratch = parent.appending(path: "Área de trabalho")
    let repo = try await makeRepository(at: scratch.appending(path: "api"), scratch: scratch)
    var harness = FakeHarness()
    harness.oneShotArguments = oneShot
    let worktrees = WorktreeModel(
        ledger: TaskLedger(store: TaskWorktreeStore(url: scratch.appending(path: "task-worktrees.json"))),
        root: scratch.appending(path: "worktrees"), defaults: scratchDefaults.defaults, maker: maker,
        registry: HarnessRegistry(harnesses: [harness]), suggester: suggester)
    let bench = Bench(chat: ChatModel(store: FileTranscriptStore(root: scratch.appending(path: "sessions")),
                                      workingDirectory: repo.checkout, harness: harness.id,
                                      cache: SessionCache(defaults: scratchDefaults.defaults),
                                      registry: HarnessRegistry(harnesses: [harness]),
                                      attachmentsRoot: scratch.appending(path: "attachments")),
                      harness: harness, worktrees: worktrees, scratch: scratch,
                      checkout: repo.checkout, defaults: scratchDefaults.defaults)
    await worktrees.prepare(bench.chat)
    try await body(bench)
    await bench.chat.stop()
}

@MainActor
@Test func aRepoFolderOffersTheWorktreeOnAnEmptySession() async throws {
    try await withBench { bench in
        #expect(bench.worktrees.isOffered(bench.chat))
        #expect(bench.worktrees.layout(for: bench.chat)?.repos.map(\.name) == ["api"])
    }
}

@MainActor
@Test func aNameAlreadyTakenGetsTheNextFreeSuffix() async throws {
    try await withBench { bench in
        try await runGit(["branch", "feat/ajusta-o-login"], in: bench.checkout)
        await bench.worktrees.prepare(bench.chat)
        bench.worktrees.setEnabled(true, for: bench.chat)

        await bench.worktrees.launch(bench.chat, text: "ajusta o login")

        #expect(bench.worktrees.worktree(for: bench.chat.sessionID)?.branch == "feat/ajusta-o-login-2")
    }
}

@MainActor
@Test func haikuNamesTheBranchWhenTheHarnessCanAsk() async throws {
    var suggester = BranchSuggester()
    suggester.run = { _, _, _ in ProcessOutcome(status: 0, stdout: Data("fix/patient-login\n".utf8), stderr: Data()) }
    try await withBench(suggester: suggester, oneShot: ["-p"]) { bench in
        bench.worktrees.setEnabled(true, for: bench.chat)

        await bench.worktrees.launch(bench.chat, text: "NS-7 ajusta o login do paciente")

        #expect(bench.worktrees.worktree(for: bench.chat.sessionID)?.branch == "fix/NS-7-patient-login")
        #expect(bench.chat.workingDirectory.lastPathComponent == "fix-NS-7-patient-login")
    }
}

@MainActor
@Test func withoutAnAnswerTheNameComesFromTheMessage() async throws {
    var suggester = BranchSuggester()
    suggester.run = { _, _, _ in nil }
    try await withBench(suggester: suggester, oneShot: ["-p"]) { bench in
        bench.worktrees.setEnabled(true, for: bench.chat)

        await bench.worktrees.launch(bench.chat, text: "ajusta o login")

        #expect(bench.worktrees.worktree(for: bench.chat.sessionID)?.branch == "feat/ajusta-o-login")
    }
}

@MainActor
@Test func launchingMovesTheSessionIntoItsWorktreeAndSendsTheMessage() async throws {
    try await withBench { bench in
        bench.worktrees.setEnabled(true, for: bench.chat)

        await bench.worktrees.launch(bench.chat, text: "NS-7 ajusta o login")

        let worktree = bench.scratch.appending(path: "worktrees/api/feat-NS-7-ajusta-o-login")
        #expect(bench.chat.workingDirectory.path == worktree.path)
        #expect(bench.harness.log.lastWorkingDirectory?.path == worktree.path)
        #expect(await bench.harness.session.sent.last?.text == "NS-7 ajusta o login")
        #expect(bench.worktrees.worktree(for: bench.chat.sessionID)?.branch == "feat/NS-7-ajusta-o-login")
        #expect(!bench.worktrees.isOffered(bench.chat))
        #expect(bench.worktrees.phase(for: bench.chat.sessionID) == nil)
        let reopened = TaskLedger(store: TaskWorktreeStore(url: bench.scratch.appending(path: "task-worktrees.json")))
        #expect(reopened.worktree(for: bench.chat.sessionID)?.sessionDirectory.path == worktree.path)
    }
}

@MainActor
@Test func aFailedCreationGivesTheTextBackAndSendsNothing() async throws {
    try await withBench { bench in
        try await runGit(["remote", "set-url", "origin", bench.scratch.appending(path: "missing.git").path],
                         in: bench.checkout)
        try await runGit(["remote", "set-head", "origin", "-d"], in: bench.checkout)
        try await runGit(["update-ref", "-d", "refs/remotes/origin/main"], in: bench.checkout)
        try await runGit(["branch", "-m", "main", "trunk"], in: bench.checkout)
        let before = bench.chat.workingDirectory
        bench.worktrees.setEnabled(true, for: bench.chat)

        await bench.worktrees.launch(bench.chat, text: "ajusta o login")

        #expect(bench.worktrees.phase(for: bench.chat.sessionID)
                == .failed("Falhou em api: não encontrei a branch padrão"))
        #expect(bench.chat.prompt == "ajusta o login")
        #expect(bench.chat.workingDirectory == before)
        #expect(await bench.harness.session.sent.isEmpty)
        #expect(bench.worktrees.worktree(for: bench.chat.sessionID) == nil)
    }
}

@MainActor
@Test func withTheChipOffTheMessageGoesOutInPlace() async throws {
    try await withBench { bench in
        bench.worktrees.setEnabled(false, for: bench.chat)
        let before = bench.chat.workingDirectory

        await bench.worktrees.launch(bench.chat, text: "oi")

        #expect(bench.chat.workingDirectory == before)
        #expect(await bench.harness.session.sent.last?.text == "oi")
        #expect(bench.worktrees.worktree(for: bench.chat.sessionID) == nil)
    }
}

@MainActor
@Test func aSessionAlreadyInAWorktreeBranchesOffUnderTheMainRepo() async throws {
    try await withBench { bench in
        bench.worktrees.setEnabled(true, for: bench.chat)
        await bench.worktrees.launch(bench.chat, text: "primeira tarefa")
        let inherited = bench.chat(in: bench.chat.workingDirectory)
        await bench.worktrees.prepare(inherited)

        await bench.worktrees.launch(inherited, text: "segunda tarefa")

        #expect(inherited.workingDirectory.path
                == bench.scratch.appending(path: "worktrees/api/feat-segunda-tarefa").path)
        #expect(bench.worktrees.worktree(for: inherited.sessionID)?.repos.first?.original.path
                == bench.checkout.path)
        await inherited.stop()
    }
}

@MainActor
@Test func theChipRemembersTheLastChoice() async throws {
    try await withBench { bench in
        bench.worktrees.setEnabled(true, for: bench.chat)
        let next = WorktreeModel(ledger: bench.worktrees.ledger, root: bench.scratch,
                                 defaults: bench.defaults)
        #expect(next.draft(for: inertChat()).isEnabled)
    }
}

@MainActor
@Test func aFolderWithManyReposStartsWithNoneChosen() async throws {
    let scratchDefaults = ScratchDefaults()
    let many = try makeTree(["r1/.git", "r2/.git", "r3/.git", "r4/.git", "r5/.git"])
    let few = try makeTree(["r1/.git", "r2/.git"])
    defer {
        scratchDefaults.remove()
        try? FileManager.default.removeItem(at: many)
        try? FileManager.default.removeItem(at: few)
    }
    let worktrees = WorktreeModel(
        ledger: TaskLedger(store: TaskWorktreeStore(url: many.appending(path: "ledger.json"))),
        root: many.appending(path: "wt"), defaults: scratchDefaults.defaults)
    let crowded = ChatModel(store: FileTranscriptStore(root: many.appending(path: ".sessions")),
                            workingDirectory: many, cache: SessionCache(defaults: scratchDefaults.defaults))
    let small = ChatModel(store: FileTranscriptStore(root: few.appending(path: ".sessions")),
                          workingDirectory: few, cache: SessionCache(defaults: scratchDefaults.defaults))
    await worktrees.prepare(crowded)
    await worktrees.prepare(small)

    worktrees.setEnabled(true, for: crowded)
    #expect(worktrees.draft(for: crowded).chosen.isEmpty)
    #expect(worktrees.blocker(for: crowded) == "Escolha ao menos um repo")
    let first = try #require(worktrees.layout(for: crowded)?.repos.first)
    worktrees.toggle(repo: first.id, for: crowded)
    #expect(worktrees.blocker(for: crowded) == nil)

    #expect(worktrees.draft(for: small).chosen.count == 2)
}

private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
}

private func gatedMaker(_ gate: Gate) -> WorktreeMaker {
    var maker = WorktreeMaker()
    maker.git = { arguments, directory, timeout in
        if arguments.first == "fetch" { await gate.wait() }
        return await WorktreeMaker.systemGit(arguments, directory, timeout)
    }
    return maker
}

@MainActor
@Test func switchingTheChipOffMidCreationNeitherUnlocksNorSendsTwice() async throws {
    let gate = Gate()
    try await withBench(maker: gatedMaker(gate)) { bench in
        let id = bench.chat.sessionID
        bench.worktrees.setEnabled(true, for: bench.chat)
        let first = Task { await bench.worktrees.launch(bench.chat, text: "primeira tarefa") }
        await waitUntil { bench.worktrees.isCreating(id) }

        bench.worktrees.setEnabled(false, for: bench.chat)
        #expect(bench.worktrees.isCreating(id))
        #expect(!bench.worktrees.canSend(bench.chat))
        await bench.worktrees.launch(bench.chat, text: "segunda")

        await gate.open()
        await first.value
        #expect(await bench.harness.session.sent.map(\.text) == ["primeira tarefa"])
    }
}

@MainActor
@Test func deletingTheSessionMidCreationSendsNothingAndLeavesNothing() async throws {
    let gate = Gate()
    try await withBench(maker: gatedMaker(gate)) { bench in
        let id = bench.chat.sessionID
        bench.worktrees.setEnabled(true, for: bench.chat)
        let launching = Task { await bench.worktrees.launch(bench.chat, text: "ajusta o login") }
        await waitUntil { bench.worktrees.isCreating(id) }

        await bench.chat.stop()
        bench.worktrees.forget(id)
        await gate.open()
        await launching.value

        #expect(bench.worktrees.worktree(for: id) == nil)
        #expect(await bench.harness.session.sent.isEmpty)
        #expect(bench.chat.workingDirectory.path == bench.checkout.path)
        #expect(!FileManager.default.fileExists(
            atPath: bench.scratch.appending(path: "worktrees/api/feat-ajusta-o-login").path))
        #expect(!(await gitSucceeds(["show-ref", "--verify", "--quiet", "refs/heads/feat/ajusta-o-login"],
                                    in: bench.checkout)))
    }
}

@MainActor
@Test func aRenameMadeByTheAgentMovesTheSessionAndItsRecord() async throws {
    try await withBench { bench in
        bench.worktrees.setEnabled(true, for: bench.chat)
        await bench.worktrees.launch(bench.chat, text: "ajusta o login")
        let made = try #require(bench.worktrees.worktree(for: bench.chat.sessionID))
        let old = try #require(made.repos.first?.worktree)
        let moved = old.deletingLastPathComponent().appending(path: "feat-fix-sign-in")
        try await runGit(["branch", "-m", made.branch, "feat/fix-sign-in"], in: bench.checkout)
        try await runGit(["worktree", "move", old.path, moved.path], in: bench.checkout)

        await bench.worktrees.reconcile(bench.chat)

        let current = try #require(bench.worktrees.worktree(for: bench.chat.sessionID))
        #expect(current.branch == "feat/fix-sign-in")
        #expect(current.repos.map { $0.worktree.resolvingSymlinksInPath().path }
                == [moved.resolvingSymlinksInPath().path])
        #expect(bench.chat.workingDirectory.resolvingSymlinksInPath().path
                == moved.resolvingSymlinksInPath().path)
        #expect(bench.chat.branch == "feat/fix-sign-in")
    }
}

@MainActor
@Test func aBranchRenameAloneRefreshesTheSessionBranch() async throws {
    try await withBench { bench in
        bench.worktrees.setEnabled(true, for: bench.chat)
        await bench.worktrees.launch(bench.chat, text: "ajusta o login")
        let made = try #require(bench.worktrees.worktree(for: bench.chat.sessionID))
        let folder = bench.chat.workingDirectory
        try await runGit(["branch", "-m", made.branch, "feat/fix-sign-in"], in: bench.checkout)

        await bench.worktrees.reconcile(bench.chat)

        #expect(bench.worktrees.worktree(for: bench.chat.sessionID)?.branch == "feat/fix-sign-in")
        #expect(bench.chat.workingDirectory == folder)
        #expect(bench.chat.branch == "feat/fix-sign-in")
    }
}

@MainActor
@Test func aSessionWithoutAWorktreeIsLeftAlone() async throws {
    try await withBench { bench in
        let folder = bench.chat.workingDirectory

        await bench.worktrees.reconcile(bench.chat)

        #expect(bench.chat.workingDirectory == folder)
        #expect(bench.worktrees.worktree(for: bench.chat.sessionID) == nil)
    }
}
