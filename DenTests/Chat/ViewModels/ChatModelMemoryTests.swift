import Testing
import Foundation
import HarnessCore
import DenStore
import DenMemory
@testable import Den

@MainActor
private func remembering(_ bench: MemoryBench) throws {
    try bench.wiki.save(MemoryPage(slug: "sem-coautor", title: "Sem coautor", category: .rule,
                                   body: "Nunca adicionar coautor.", created: Date(), updated: Date()),
                        in: .user)
}

@MainActor
private func typedLines(of chat: ChatModel) -> [String] {
    chat.entries.compactMap { entry in
        if case .userMessage(let text, _) = entry.kind { return text }
        return nil
    }
}

@Test func theFirstTurnOfANewSessionCarriesTheMemory() async throws {
    try await withMemory { bench in
        try remembering(bench)
        try await withLiveChat { live in
            live.chat.memory = bench.memory

            await live.chat.send(text: "arruma o login")
            await live.chat.send(text: "e agora o logout")

            let sent = await live.session.sent.map(\.text)
            #expect(sent.count == 2)
            #expect(sent[0].hasPrefix("<den-memory>\n"))
            #expect(sent[0].contains("### Sem coautor (Regras)\nNunca adicionar coautor.\n"))
            #expect(sent[0].hasSuffix("</den-memory>\n\narruma o login"))
            #expect(sent[1] == "e agora o logout")
            #expect(typedLines(of: live.chat) == ["arruma o login", "e agora o logout"])
        }
    }
}

@Test func aCommandGoesOutBareAndTheNextTurnCarriesTheMemory() async throws {
    try await withMemory { bench in
        try remembering(bench)
        try await withLiveChat { live in
            live.chat.memory = bench.memory

            await live.chat.send(text: "/model")
            await live.chat.send(text: "agora sim")

            let sent = await live.session.sent.map(\.text)
            #expect(sent[0] == "/model")
            #expect(sent[1].hasPrefix("<den-memory>\n"))
            #expect(sent[1].hasSuffix("\n\nagora sim"))
        }
    }
}

@Test func withNothingRememberedOrWithMemoryOffTheTextGoesUntouched() async throws {
    try await withMemory { bench in
        try await withLiveChat { live in
            live.chat.memory = bench.memory
            await live.chat.send(text: "wiki vazia")
            #expect(await live.session.sent.map(\.text) == ["wiki vazia"])
        }
        try remembering(bench)
        bench.memory.isEnabled = false
        try await withLiveChat { live in
            live.chat.memory = bench.memory
            await live.chat.send(text: "memória desligada")
            #expect(await live.session.sent.map(\.text) == ["memória desligada"])
        }
        try await withLiveChat { live in
            await live.chat.send(text: "sem modelo de memória")
            #expect(await live.session.sent.map(\.text) == ["sem modelo de memória"])
        }
    }
}

@Test func aResumedSessionIsNotToldAgain() async throws {
    try await withMemory { bench in
        try remembering(bench)
        var harness = FakeHarness()
        harness.declaredCapabilities.canResumeSession = true
        let earlier = Segment(harness: harness.id, harnessSessionID: UUID().uuidString, model: "m",
                              entries: [typed("antes"), assistant("resposta de antes").entry])
        let chat = ChatModel(store: scratchSessions(),
                             restoring: Session(title: "retomada", workingDirectory: bench.repository,
                                                segments: [earlier]),
                             cache: scratchCache, registry: HarnessRegistry(harnesses: [harness]))
        chat.memory = bench.memory

        await chat.send(text: "continuando")
        await chat.stop()

        #expect(await harness.session.starts == [.resume(harnessSessionID: earlier.harnessSessionID)])
        #expect(await harness.session.sent.map(\.text) == ["continuando"])
    }
}

@Test func threeTurnsOfConversationTriggerACapture() async throws {
    try await withMemory { bench in
        bench.asked.answer(twoMemories)
        try await withLiveChat { live in
            live.chat.memory = bench.memory

            for turn in 1...3 {
                #expect(bench.asked.instructions.isEmpty)
                await live.chat.send(text: "mensagem \(turn)")
                await live.session.emit(assistant("resposta \(turn)"))
                await live.session.emit(endOfTurn())
                await settle { !live.chat.isBusy }
            }
            await settle { bench.memory.status == .saved(1) }

            #expect(bench.asked.instructions.count == 1)
            #expect(bench.asked.instructions[0].contains("**Você:** mensagem 3"))
            #expect(bench.memory.pages(in: .user).map(\.title) == ["Sem coautor"])
        }
    }
}

@Test func aTurnThatEndsInErrorDoesNotTriggerACapture() async throws {
    try await withMemory { bench in
        bench.asked.answer(twoMemories)
        try await withLiveChat { live in
            live.chat.memory = bench.memory

            for turn in 1...3 {
                await live.chat.send(text: "mensagem \(turn)")
                await live.session.emit(endOfTurn(isError: true))
                await settle { !live.chat.isBusy }
            }

            #expect(bench.asked.instructions.isEmpty)
        }
    }
}

@Test func leavingASessionCapturesWhatWasSaidInIt() async throws {
    try await withMemory { bench in
        bench.asked.answer(twoMemories)
        let repositories = scratchRepositories()
        let workspace = WorkspaceModel(store: repositories.sessions, sidebar: repositories.sidebar,
                                       defaults: bench.scratch.defaults, cache: SessionCache(repositories),
                                       registry: HarnessRegistry(harnesses: [bench.harness]),
                                       attachmentsRoot: bench.root.appending(path: "attachments"),
                                       memory: bench.memory)
        workspace.workingDirectory = bench.repository

        await workspace.newSession()
        let first = try #require(workspace.active)
        await first.send(text: "neste projeto os commits são convencionais")
        await bench.harness.session.emit(assistant("Anotado."))
        await settle { first.entries.count == 2 }
        #expect(bench.asked.instructions.isEmpty)

        await workspace.select(first.sessionID)
        #expect(bench.asked.instructions.isEmpty)

        await workspace.newSession()
        await settle { bench.memory.status == .saved(2) }

        #expect(bench.asked.instructions.count == 1)
        #expect(bench.asked.instructions[0].contains("os commits são convencionais"))
        await workspace.stopAll()
    }
}
