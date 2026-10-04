import Testing
import Foundation
import Synchronization
import HarnessCore
import DenStore
import DenMemory
@testable import Den

nonisolated final class Asked: Sendable {
    private let state = Mutex<(instructions: [String], executables: [String], reply: String?)>(([], [], nil))

    var instructions: [String] { state.withLock { $0.instructions } }
    var executables: [String] { state.withLock { $0.executables } }

    func answer(_ reply: String?) {
        state.withLock { $0.reply = reply }
    }

    func run(_ executable: String, _ arguments: [String]) -> ProcessOutcome? {
        state.withLock { state in
            state.instructions.append(arguments.last ?? "")
            state.executables.append(executable)
            return state.reply.map { ProcessOutcome(status: 0, stdout: Data($0.utf8), stderr: Data()) }
        }
    }
}

@MainActor
struct MemoryBench {
    let memory: MemoryModel
    let repositories: Repositories
    let wiki: FileMemoryRepository
    let asked: Asked
    let root: URL
    let repository: URL
    let harness: FakeHarness
    let scratch: ScratchDefaults

    var project: ProjectIdentity { ProjectIdentity(root: repository) }

    func rebuilt() -> MemoryModel {
        MemoryModel(repository: wiki, marks: repositories.memoryMarks, defaults: scratch.defaults,
                    registry: HarnessRegistry(harnesses: [harness]),
                    run: { [asked] executable, arguments, _ in asked.run(executable, arguments) })
    }

    func capture(_ entries: [TranscriptEntry], session: UUID = UUID(), atLeast threshold: Int = 3,
                 in directory: URL? = nil, with model: MemoryModel? = nil) async {
        await (model ?? memory).capture(session: session, entries: entries, directory: directory ?? repository,
                                        harness: harness.id, atLeast: threshold)
    }
}

@MainActor
func withMemory(harnesses: [FakeHarness]? = nil,
                _ body: (MemoryBench) async throws -> Void) async throws {
    let root = try makeTree(["code/den/.git", "code/den/Sources", "downloads"])
    let scratch = ScratchDefaults()
    defer {
        scratch.remove()
        try? FileManager.default.removeItem(at: root)
    }
    var talker = FakeHarness()
    talker.quickPrompt = ["-p"]
    let registered = harnesses ?? [talker]
    let asked = Asked()
    let repositories = scratchRepositories()
    let wiki = FileMemoryRepository(root: root.appending(path: "memory"))
    let memory = MemoryModel(repository: wiki, marks: repositories.memoryMarks, defaults: scratch.defaults,
                             registry: HarnessRegistry(harnesses: registered),
                             run: { executable, arguments, _ in asked.run(executable, arguments) })
    try await body(MemoryBench(memory: memory, repositories: repositories, wiki: wiki, asked: asked,
                               root: root, repository: root.appending(path: "code/den"),
                               harness: registered[0], scratch: scratch))
}

func typed(_ text: String) -> TranscriptEntry {
    TranscriptEntry(timestamp: Date(), kind: .userMessage(text: text, attachments: []), raw: .null)
}

func chatter(_ prefix: String, turns: Int = 3) -> [TranscriptEntry] {
    (1...turns).flatMap { [typed("\(prefix) \($0)"), assistant("ok \(prefix) \($0)").entry] }
}

extension SessionUpdate {
    var entry: TranscriptEntry {
        guard case .entry(let entry) = self else { fatalError("not an entry update") }
        return entry
    }
}

let twoMemories = """
    {"memories": [
      {"layer": "project", "category": "convention", "title": "Commits convencionais", "body": "tipo(escopo): descrição", "page": ""},
      {"layer": "user", "category": "rule", "title": "Sem coautor", "body": "Nunca adicionar coautor.", "page": ""}
    ]}
    """

@Test func aCaptureWritesPagesAndRemembersHowFarItRead() async throws {
    try await withMemory { bench in
        bench.asked.answer(twoMemories)
        let session = UUID()
        let entries = chatter("convenção")

        await bench.capture(entries, session: session)

        #expect(bench.memory.status == .saved(2))
        #expect(bench.memory.revision == 1)
        #expect(bench.wiki.pages(in: .project(bench.project)).map(\.title) == ["Commits convencionais"])
        #expect(bench.wiki.pages(in: .user).map(\.sessions) == [[session]])
        #expect(bench.memory.pages(in: .user).map(\.title) == ["Sem coautor"])

        await bench.capture(entries, session: session)
        #expect(bench.asked.instructions.count == 1)
    }
}

@Test func belowTheThresholdNothingIsAsked() async throws {
    try await withMemory { bench in
        bench.asked.answer(twoMemories)

        await bench.capture(chatter("pouco", turns: 2))
        #expect(bench.asked.instructions.isEmpty)
        #expect(bench.memory.status == .idle)

        await bench.capture(chatter("pouco", turns: 2), atLeast: 2)
        #expect(bench.asked.instructions.count == 1)
        await bench.capture([])
        #expect(bench.asked.instructions.count == 1)
    }
}

@Test func onlyWhatIsNewIsSentTheSecondTime() async throws {
    try await withMemory { bench in
        bench.asked.answer("{\"memories\": []}")
        let session = UUID()
        let first = chatter("antiga")
        await bench.capture(first, session: session)
        #expect(bench.memory.status == .nothingNew)
        #expect(bench.memory.revision == 0)

        await bench.capture(first + chatter("recente"), session: session)

        #expect(bench.asked.instructions.count == 2)
        #expect(bench.asked.instructions[1].contains("**Você:** recente 1"))
        #expect(!bench.asked.instructions[1].contains("antiga"))
    }
}

@Test func aReplyThatCannotBeReadOrACallThatFailsLeavesTheMarkWhereItWas() async throws {
    try await withMemory { bench in
        let session = UUID()
        let entries = chatter("tentativa")

        bench.asked.answer("desculpe, não entendi")
        await bench.capture(entries, session: session)
        #expect(bench.memory.status == .failed("a resposta do harness não veio no formato esperado"))

        bench.asked.answer(nil)
        await bench.capture(entries, session: session)
        #expect(bench.memory.status == .failed("a chamada ao harness falhou"))

        bench.asked.answer(twoMemories)
        await bench.capture(entries, session: session)
        #expect(bench.memory.status == .saved(2))
        #expect(bench.asked.instructions.count == 3)
    }
}

@Test func switchedOffItNeitherAsksNorTells() async throws {
    try await withMemory { bench in
        try bench.wiki.save(MemoryPage(slug: "regra", title: "Regra", category: .rule, body: "corpo",
                                       created: Date(), updated: Date()), in: .user)
        #expect(bench.memory.isEnabled)
        #expect(bench.memory.preamble(for: bench.repository) != nil)

        bench.memory.isEnabled = false
        bench.asked.answer(twoMemories)
        await bench.capture(chatter("desligada"))

        #expect(bench.asked.instructions.isEmpty)
        #expect(bench.memory.preamble(for: bench.repository) == nil)
        #expect(!bench.rebuilt().isEnabled)
    }
}

@Test func aConversationIsOnlyEverSentToItsOwnHarness() async throws {
    var talker = FakeHarness(id: "talker")
    talker.quickPrompt = ["--ask"]
    try await withMemory(harnesses: [FakeHarness(id: "silent"), talker]) { bench in
        bench.asked.answer(twoMemories)

        await bench.capture(chatter("não emprestado"))

        #expect(bench.asked.instructions.isEmpty)
        #expect(bench.memory.status == .failed("este harness não faz a chamada avulsa que a memória usa"))
        #expect(bench.wiki.pages(in: .user).isEmpty)
    }
}

@Test func theSessionsOwnHarnessIsTheOneAsked() async throws {
    var talker = FakeHarness(id: "talker")
    talker.quickPrompt = ["--ask"]
    try await withMemory(harnesses: [talker, FakeHarness(id: "silent")]) { bench in
        bench.asked.answer(twoMemories)

        await bench.capture(chatter("próprio"))

        #expect(bench.memory.status == .saved(2))
        #expect(bench.asked.executables == ["/fake/bin/harness"])
    }
}

@MainActor
private final class Switch {
    var memory: MemoryModel?

    func off() { memory?.isEnabled = false }
}

@Test func switchingMemoryOffWhileItCapturesSavesNothing() async throws {
    try await withMemory { bench in
        let reply = twoMemories
        let memorySwitch = Switch()
        let memory = MemoryModel(repository: bench.wiki, marks: bench.repositories.memoryMarks,
                                 defaults: bench.scratch.defaults,
                                 registry: HarnessRegistry(harnesses: [bench.harness]),
                                 run: { _, _, _ in
                                     await memorySwitch.off()
                                     return ProcessOutcome(status: 0, stdout: Data(reply.utf8), stderr: Data())
                                 })
        memorySwitch.memory = memory

        await bench.capture(chatter("no meio"), with: memory)

        #expect(!memory.isEnabled)
        #expect(bench.wiki.pages(in: .user).isEmpty)
        #expect(bench.wiki.pages(in: .project(bench.project)).isEmpty)
        #expect(memory.status == .idle)
    }
}

@Test func askingForACaptureWithNothingNewSaysSo() async throws {
    try await withMemory { bench in
        bench.asked.answer(twoMemories)
        let session = UUID()

        await bench.memory.capture(session: session, entries: [assistant("só o assistente").entry],
                                   directory: bench.repository, harness: bench.harness.id,
                                   atLeast: MemoryModel.leaveThreshold, announcing: true)
        #expect(bench.memory.status == .nothingNew)
        #expect(bench.asked.instructions.isEmpty)

        await bench.memory.capture(session: session, entries: chatter("agora há", turns: 1),
                                   directory: bench.repository, harness: bench.harness.id,
                                   atLeast: MemoryModel.leaveThreshold, announcing: true)
        #expect(bench.memory.status == .saved(2))
    }
}

@Test func theMarkOfAStoredSessionSurvivesANewModel() async throws {
    try await withMemory { bench in
        bench.asked.answer(twoMemories)
        let session = storedSession("lembrada")
        try await bench.repositories.sessions.saveMetadata(session)
        let entries = chatter("persistida")
        await bench.capture(entries, session: session.id)

        await bench.capture(entries, session: session.id, with: bench.rebuilt())

        #expect(bench.asked.instructions.count == 1)
    }
}

@Test func whatANewSessionIsToldDependsOnWhereItRuns() async throws {
    try await withMemory { bench in
        #expect(bench.memory.preamble(for: bench.repository) == nil)
        bench.asked.answer(twoMemories)
        await bench.capture(chatter("contexto"))

        let inside = try #require(bench.memory.preamble(for: bench.repository.appending(path: "Sources")))
        let outside = try #require(bench.memory.preamble(for: bench.root.appending(path: "downloads")))

        #expect(inside.contains("## Memória do usuário\n### Sem coautor (Regras)"))
        #expect(inside.contains("## Memória do projeto den\n### Commits convencionais (Convenções)"))
        #expect(outside.contains("Sem coautor"))
        #expect(!outside.contains("Memória do projeto"))
        #expect(bench.memory.project(for: bench.root.appending(path: "downloads")) == nil)
    }
}

@Test func aProjectFactFromOutsideARepositoryIsNotKept() async throws {
    try await withMemory { bench in
        bench.asked.answer(twoMemories)

        await bench.capture(chatter("solta"), in: bench.root.appending(path: "downloads"))

        #expect(bench.memory.status == .saved(1))
        #expect(bench.asked.instructions[0].contains("use somente a camada \"user\""))
        #expect(bench.wiki.pages(in: .project(bench.project)).isEmpty)
    }
}

@Test func deletingAPageRemovesItFromTheWiki() async throws {
    try await withMemory { bench in
        bench.asked.answer(twoMemories)
        await bench.capture(chatter("apagar"))
        let page = try #require(bench.memory.pages(in: .user).first)
        #expect(bench.memory.file(for: page, in: .user).lastPathComponent == "sem-coautor.md")
        #expect(bench.memory.directory(of: .user).lastPathComponent == "user")

        bench.memory.delete(page, in: .user)

        #expect(bench.memory.pages(in: .user).isEmpty)
        #expect(bench.memory.revision == 2)
    }
}
