import Testing
import Foundation
import HarnessCore
@testable import Den

private func notices(_ chat: ChatModel) -> [String] {
    chat.lines.filter { "\($0.role)" == "notice" }.map(\.text)
}

@Test func startDiscoversTheHarnessAndOpensASession() async throws {
    try await withLiveChat { live in
        await live.chat.start()

        #expect(live.chat.isLive)
        #expect(live.chat.status == "pronta")
        #expect(live.log.madeSessions == 1)
        #expect(await live.session.starts == [.fresh])
        #expect(live.log.lastWorkingDirectory?.path == live.chat.workingDirectory.path)
    }
}

@Test func startIsIgnoredWhenASessionIsAlreadyLive() async throws {
    try await withLiveChat { live in
        await live.chat.start()
        await live.chat.start()
        #expect(live.log.madeSessions == 1)
    }
}

@Test func anUnknownHarnessFailsLoudly() async {
    let store = FileTranscriptStore(root: FileManager.default.temporaryDirectory)
    let chat = ChatModel(store: store,
                         workingDirectory: FileManager.default.temporaryDirectory,
                         harness: HarnessID(rawValue: "ghost"),
                         cache: scratchCache,
                         registry: HarnessRegistry(harnesses: []))
    await chat.start()

    #expect(chat.isLive == false)
    #expect(chat.status == "falhou: harness desconhecido")
    #expect(notices(chat) == ["não conheço o harness ghost"])
}

@Test func aFailedDiscoveryLeavesANoticeAndStaysCold() async throws {
    try await withLiveChat(configure: { harness in
        harness.discoveryFailure = HarnessFailure(reason: "binary missing")
    }, { live in
        await live.chat.start()

        #expect(live.chat.isLive == false)
        #expect(live.chat.status.hasPrefix("falhou:"))
        #expect(notices(live.chat).first?.hasPrefix("não consegui subir o harness:") == true)
        #expect(live.log.madeSessions == 0)
    })
}

@Test func knobsComeFromTheLiveSessionOnceItIsUp() async throws {
    let offered = [HarnessKnob(id: "mode", category: .mode, name: "Modo",
                               currentValue: "auto",
                               options: [.init(value: "auto", label: "Auto")])]
    try await withLiveChat { live in
        await live.session.offer(knobs: offered)
        await live.chat.start()
        #expect(live.chat.knobs == offered)
    }
}

@Test func sendStartsTheSessionAndForwardsTheText() async throws {
    try await withLiveChat { live in
        live.chat.prompt = "  build it  "
        await live.chat.send()

        #expect(live.chat.isLive)
        #expect(await live.session.sent.map(\.text) == ["build it"])
        #expect(live.chat.prompt.isEmpty)
        #expect(live.chat.isBusy)
        #expect(live.chat.lines.map(\.text) == ["build it"])
    }
}

@Test func sendIgnoresAnEmptyPrompt() async throws {
    try await withLiveChat { live in
        live.chat.prompt = "   "
        await live.chat.send()

        #expect(live.chat.isLive == false)
        #expect(await live.session.sent.isEmpty)
        #expect(live.chat.isBusy == false)
    }
}

@Test func anExplicitTextWinsOverThePrompt() async throws {
    try await withLiveChat { live in
        live.chat.prompt = "typed but unsent"
        await live.chat.send(text: "explicit")
        #expect(await live.session.sent.map(\.text) == ["explicit"])
    }
}

@Test func aFailedSendLeavesANoticeAndClearsBusy() async throws {
    try await withLiveChat { live in
        await live.chat.start()
        await live.session.failSend(HarnessFailure(reason: "pipe closed"))

        await live.chat.send(text: "doomed")

        #expect(live.chat.isBusy == false)
        #expect(live.chat.turnStartedAt == nil)
        #expect(notices(live.chat).last?.hasPrefix("não consegui mandar o turno:") == true)
    }
}

@Test func theCompactCommandSkipsTheTranscriptButStillGoesOut() async throws {
    try await withLiveChat { live in
        await live.chat.send(text: SlashCatalog.compactCommand)

        #expect(live.chat.compactingSince != nil)
        #expect(live.chat.lines.isEmpty)
        #expect(await live.session.sent.map(\.text) == [SlashCatalog.compactCommand])
    }
}

@Test func attachmentsRideAlongTheTurnAndLeaveTheTray() async throws {
    try await withLiveChat { live in
        live.chat.attach(imageData: Data([0x89, 0x50]))
        await live.chat.send(text: "look")

        let turn = try #require(await live.session.sent.first)
        #expect(turn.attachments.map(\.mediaType) == ["image/png"])
        #expect(live.chat.pendingAttachments.isEmpty)
    }
}

@Test func sentAttachmentsAreStoredUnderTheInjectedRoot() async throws {
    try await withLiveChat { live in
        live.chat.attach(imageData: Data([0x89, 0x50]))
        live.chat.attach(fileData: Data("x".utf8), name: "notes.txt",
                         mediaType: "text/plain")
        await live.chat.send(text: "look")

        let stored = try FileManager.default.contentsOfDirectory(
            at: live.attachments, includingPropertiesForKeys: nil)
        #expect(stored.map(\.pathExtension).sorted() == ["png", "txt"])
    }
}

@Test func anAttachmentAloneIsEnoughToSend() async throws {
    try await withLiveChat { live in
        live.chat.attach(fileData: Data("x".utf8), name: "notes.txt",
                         mediaType: "text/plain")
        await live.chat.send()
        #expect(await live.session.sent.count == 1)
    }
}

@Test func removeAttachmentTakesItOutOfTheTray() async throws {
    try await withLiveChat { live in
        live.chat.attach(imageData: Data([0x01]))
        let pending = try #require(live.chat.pendingAttachments.first)
        live.chat.removeAttachment(pending.id)
        #expect(live.chat.pendingAttachments.isEmpty)
    }
}

private let request = PermissionRequest(
    id: "req-1", toolName: "Bash", input: .object([:]),
    options: [.init(id: "allow", kind: .allowOnce, label: "Permitir"),
              .init(id: "deny", kind: .rejectOnce, label: "Negar")])

@Test func resolvingWithAnOptionForwardsItsIdentifier() async throws {
    try await withLiveChat { live in
        await live.chat.start()
        live.chat.pending = request

        await live.chat.resolve(request.options[0])

        #expect(live.chat.pending == nil)
        let sent = await live.session.decisions
        #expect(sent.map(\.request) == ["req-1"])
        #expect(sent.map(\.decision) == [.option(id: "allow")])
    }
}

@Test func allowAndDenyPickTheMatchingOption() async throws {
    try await withLiveChat { live in
        await live.chat.start()

        live.chat.pending = request
        await live.chat.resolve(allow: true)
        live.chat.pending = request
        await live.chat.resolve(allow: false)

        let sent = await live.session.decisions
        #expect(sent.map(\.decision) == [.option(id: "allow"), .option(id: "deny")])
    }
}

@Test func resolvingWithoutARequestDoesNothing() async throws {
    try await withLiveChat { live in
        await live.chat.start()
        await live.chat.resolve(allow: true)
        #expect(await live.session.decisions.isEmpty)
    }
}

@Test func aFailedResolveLeavesTheRequestClearedAndANotice() async throws {
    try await withLiveChat { live in
        await live.chat.start()
        await live.session.failResolve(HarnessFailure(reason: "channel gone"))
        live.chat.pending = request

        await live.chat.resolve(allow: true)

        #expect(live.chat.pending == nil)
        #expect(notices(live.chat).last?.hasPrefix("não consegui responder a permissão:") == true)
    }
}

@Test func dismissingAQuestionDeniesItWithAMessage() async throws {
    let prompt = try #require(QuestionPrompt(from: routeQuestion(id: "q-1")))

    try await withLiveChat { live in
        await live.chat.start()
        live.chat.pendingQuestion = prompt

        await live.chat.dismissQuestion()

        #expect(live.chat.pendingQuestion == nil)
        let sent = await live.session.decisions
        #expect(sent.map(\.request) == ["q-1"])
        #expect(sent.map(\.decision)
                == [.deny(message: "o usuário dispensou a pergunta", interrupt: false)])
    }
}

private let modeKnob = HarnessKnob(
    id: "mode", category: .mode, name: "Modo", currentValue: "manual",
    options: [.init(value: "manual", label: "Manual"), .init(value: "auto", label: "Auto")])

@Test func aKnobIsAppliedInPlaceWhenTheSessionSupportsIt() async throws {
    try await withLiveChat(configure: { harness in
        harness.declaredCapabilities = HarnessCapabilities(canSetPermissionMode: true)
        harness.declaredKnobs = [modeKnob]
    }, { live in
        await live.session.offer(knobs: [modeKnob])
        await live.chat.start()

        await live.chat.choose(knob: "mode", value: "auto")

        #expect(await live.session.appliedKnobs.map(\.id) == ["mode"])
        #expect(live.log.madeSessions == 1)
    })
}

@Test func aKnobRelaunchesTheSessionWhenItCannotBeSetInPlace() async throws {
    try await withLiveChat(configure: { harness in
        harness.declaredCapabilities = HarnessCapabilities(canSetPermissionMode: false)
        harness.declaredKnobs = [modeKnob]
    }, { live in
        await live.chat.start()

        await live.chat.choose(knob: "mode", value: "auto")

        #expect(await live.session.appliedKnobs.isEmpty)
        #expect(live.log.madeSessions == 2)
        #expect(await live.session.stops == 1)
    })
}

private let effortKnob = HarnessKnob(
    id: "effort", category: .effort, name: "Esforço", currentValue: "low",
    options: [.init(value: "low", label: "Baixo"), .init(value: "high", label: "Alto")])

@Test func effortRelaunchesWhenOnlyThePermissionModeCanChangeInPlace() async throws {
    try await withLiveChat(configure: { harness in
        harness.declaredCapabilities = HarnessCapabilities(canSetPermissionMode: true)
        harness.declaredKnobs = [effortKnob]
    }, { live in
        await live.session.offer(knobs: [effortKnob])
        await live.chat.start()

        await live.chat.choose(knob: "effort", value: "high")

        #expect(await live.session.appliedKnobs.isEmpty)
        #expect(live.log.madeSessions == 2)
        #expect(live.log.lastSettings["effort"] == "high")
    })
}

@Test func effortIsAppliedInPlaceWhenTheHarnessCanChangeIt() async throws {
    try await withLiveChat(configure: { harness in
        harness.declaredCapabilities = HarnessCapabilities(canSetEffortInSession: true)
        harness.declaredKnobs = [effortKnob]
    }, { live in
        await live.session.offer(knobs: [effortKnob])
        await live.chat.start()

        await live.chat.choose(knob: "effort", value: "high")

        #expect(await live.session.appliedKnobs.map(\.id) == ["effort"])
        #expect(live.log.madeSessions == 1)
    })
}

@Test func aKnobChosenMidTurnRelaunchesOnceTheTurnEnds() async throws {
    try await withLiveChat(configure: { harness in
        harness.declaredCapabilities = HarnessCapabilities(canSetPermissionMode: false)
        harness.declaredKnobs = [modeKnob]
    }, { live in
        await live.session.offer(knobs: [modeKnob])
        await live.chat.send(text: "working")

        await live.chat.choose(knob: "mode", value: "auto")
        #expect(live.log.madeSessions == 1)

        await live.session.emit(.entry(TranscriptEntry(
            timestamp: Date(),
            kind: .turnResult(TurnResult(usage: .zero, stopReason: "end_turn", isError: false)),
            raw: .object([:]))))

        await settle { live.log.madeSessions == 2 }
        #expect(live.log.lastSettings["mode"] == "auto")
    })
}

@Test func choosingTheValueAKnobAlreadyHasIsANoOp() async throws {
    try await withLiveChat(configure: { harness in
        harness.declaredCapabilities = HarnessCapabilities(canSetPermissionMode: true)
        harness.declaredKnobs = [modeKnob]
    }, { live in
        await live.chat.start()

        await live.chat.choose(knob: "mode", value: "auto")
        await live.chat.choose(knob: "mode", value: "auto")

        #expect(await live.session.appliedKnobs.count == 1)
    })
}

@Test func aChosenKnobReachesTheRelaunchedProcess() async throws {
    try await withLiveChat(configure: { harness in
        harness.declaredCapabilities = HarnessCapabilities(canSetPermissionMode: false)
        harness.declaredKnobs = [modeKnob]
    }, { live in
        await live.chat.start()
        #expect(live.log.lastSettings["mode"] == nil)

        await live.chat.choose(knob: "mode", value: "auto")

        #expect(live.log.lastSettings["mode"] == "auto",
                "a relaunch is the only way the choice reaches a CLI that cannot take it in flight")
    })
}

@Test func switchingHarnessOpensAFreshSegmentOnTheNewOne() async throws {
    let other = FakeHarness(id: "other", displayName: "Other")
    try await withLiveChat(alongside: [other]) { live in
        await live.chat.start()
        #expect(live.chat.canSwitchHarness)

        await live.chat.switchHarness(to: other.id)

        #expect(live.chat.harness == other.id)
        #expect(live.chat.harnessName == "Other")
        #expect(await live.session.stops == 1)
        #expect(other.log.madeSessions == 1)
    }
}

@Test func switchingToAnUnknownHarnessIsRefused() async throws {
    try await withLiveChat { live in
        await live.chat.start()
        await live.chat.switchHarness(to: HarnessID(rawValue: "ghost"))
        #expect(live.chat.harness == live.harness.id)
    }
}

@Test func switchingIsRefusedWhileATurnIsInFlight() async throws {
    let other = FakeHarness(id: "other", displayName: "Other")
    try await withLiveChat(alongside: [other]) { live in
        await live.chat.send(text: "working")
        #expect(live.chat.isBusy)
        #expect(live.chat.canSwitchHarness == false)
    }
}

@Test func aLoneHarnessCannotBeSwitchedAway() async throws {
    try await withLiveChat { live in
        #expect(live.chat.availableHarnesses.count == 1)
        #expect(live.chat.canSwitchHarness == false)
    }
}

@Test func stopClosesTheSessionAndGoesCold() async throws {
    try await withLiveChat { live in
        await live.chat.send(text: "hello")
        await live.chat.stop()

        #expect(live.chat.isLive == false)
        #expect(live.chat.isBusy == false)
        #expect(live.chat.turnStartedAt == nil)
        #expect(live.chat.status == "fria")
        #expect(await live.session.stops == 1)
    }
}

@Test func theInitialisationEventFillsInTheModelAndCatalog() async throws {
    try await withLiveChat { live in
        await live.chat.start()
        await live.session.emit(.event(.sessionInitialized(
            model: "opus", harnessSessionID: "abc",
            catalog: CommandCatalog(skills: ["review"], supportsCompact: true))))

        await settle { live.chat.model == "opus" }
        #expect(live.chat.model == "opus")
        #expect(live.chat.catalog.skills == ["review"])
    }
}

@Test func contextUsageReachesTheModel() async throws {
    try await withLiveChat { live in
        await live.chat.start()
        await live.session.emit(.event(.contextUsage(tokens: 4_200)))

        await settle { live.chat.contextTokens == 4_200 }
        #expect(live.chat.contextTokens == 4_200)
    }
}

@Test func aPermissionUpdateBecomesAPendingRequest() async throws {
    try await withLiveChat { live in
        await live.chat.start()
        await live.session.emit(.permission(request))

        await settle { live.chat.pending != nil }
        #expect(live.chat.pending?.id == "req-1")
    }
}

@Test func theEndedUpdateCoolsTheSessionDown() async throws {
    try await withLiveChat { live in
        await live.chat.start()
        await live.session.emit(.ended(error: "crashed"))

        await settle { live.chat.isLive == false }
        #expect(live.chat.isLive == false)
        #expect(live.chat.status == "encerrada: crashed")
        #expect(notices(live.chat).last == "a sessão caiu: crashed")
    }
}

@Test func aQuestionShapedInputDoesNotHijackAnOrdinaryTool() async throws {
    let disguised = PermissionRequest(
        id: "req-2", toolName: "Bash",
        input: .object(["questions": .array([.object([
            "question": .string("Rodar isso?"),
            "header": .string("Bash"),
            "options": .array([.object(["label": .string("Sim")])]),
        ])])]),
        options: [.init(id: "allow", kind: .allowOnce, label: "Permitir")])

    try await withLiveChat { live in
        await live.chat.start()
        await live.session.emit(.permission(disguised))

        await settle { live.chat.pending != nil }
        #expect(live.chat.pending?.id == "req-2")
        #expect(live.chat.pendingQuestion == nil,
                "the tool name alone decides which card opens, never the shape of its input")
    }
}

@Test func anAskUserQuestionPermissionOpensTheQuestionCard() async throws {
    let asking = routeQuestion(id: "req-3")

    try await withLiveChat { live in
        await live.chat.start()
        await live.session.emit(.permission(asking))

        await settle { live.chat.pendingQuestion != nil }
        #expect(live.chat.pendingQuestion?.id == "req-3")
        #expect(live.chat.pending == nil)
    }
}
