import Testing
import Foundation
import HarnessCore
@testable import DevSpace

// These run the real ClaudeCodeHarness, ControlChannel and ProcessTransport
// against a FakeCLI that replays sessions recorded from the actual CLI.

private let recordedSessionID = "051f6a7e-34f2-4dc7-bafc-27a72a020893"

private func notices(_ chat: ChatModel) -> [String] {
    chat.lines.filter { $0.role == .notice }.map(\.text)
}

private func json(_ line: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
}

private func argument(after flag: String, in launch: FakeCLI.Launch?) -> String? {
    guard let arguments = launch?.arguments,
          let index = arguments.firstIndex(of: flag),
          arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

// MARK: - A turn

@Test func theRegistryPinsTheHarnessesTheAppShips() {
    #expect(HarnessRegistry.standard.ids == [claudeCodeID, openCodeID])
}

@Test func aNewConversationLaunchesTheCLIInItsProject() async throws {
    try await withEndToEnd { e2e in
        let chat = try await e2e.newChat()

        #expect(chat.isLive)
        let launch = try #require(e2e.claude.launches.first)
        #expect(URL(filePath: launch.directory).resolvingSymlinksInPath().path
                == e2e.project.resolvingSymlinksInPath().path)
        #expect(Array(launch.arguments.prefix(9)) == [
            "-p", "--output-format", "stream-json", "--input-format", "stream-json",
            "--include-partial-messages", "--verbose", "--permission-prompt-tool", "stdio",
        ])
        #expect(argument(after: "--session-id", in: launch) != nil)
    }
}

@Test func aRecordedTurnPlaysThroughTheRealProcess() async throws {
    try await withEndToEnd { e2e in
        try e2e.claude.on(FakeCLI.userTurn, reply: RecordedSession.claude("hello"))
        let chat = try await e2e.newChat()

        await chat.send(text: "Diga apenas OK e nada mais.")
        await settle(within: processPatience) { !chat.isBusy }

        #expect(chat.lines.map(\.role) == [.user, .assistant])
        #expect(chat.lines.map(\.text) == ["Diga apenas OK e nada mais.", "OK"])
        #expect(chat.model == "claude-opus-5")
        #expect(try e2e.claude.received.map(json) == [
            json(#"{"type":"user","message":{"role":"user","content":"Diga apenas OK e nada mais."}}"#),
        ])
    }
}

@Test func anAttachmentTravelsAsABase64Block() async throws {
    try await withEndToEnd { e2e in
        let chat = try await e2e.newChat()
        chat.attach(imageData: Data([0x89, 0x50]))

        await chat.send(text: "look")
        await settle(within: processPatience) { !e2e.claude.received.isEmpty }

        let turn = try #require(e2e.claude.received.first)
        #expect(turn.contains(#""type":"image""#))
        #expect(turn.contains(#""media_type":"image/png""#))
        #expect(turn.contains(Data([0x89, 0x50]).base64EncodedString()))
        #expect(chat.lines.first?.images.count == 1)
    }
}

@Test func theTitleComesFromAOneShotRunOfTheSameCLI() async throws {
    try await withEndToEnd { e2e in
        try e2e.claude.answerTitles(with: "\"Saudação curta\"\n")
        try e2e.claude.on(FakeCLI.userTurn, reply: RecordedSession.claude("hello"))
        let chat = try await e2e.newChat()

        await chat.send(text: "Diga apenas OK e nada mais.")
        await settle(within: processPatience) { chat.title == "Saudação curta" }

        let listed = e2e.relaunched()
        await listed.refresh()
        #expect(listed.summaries.map(\.title) == ["Saudação curta"])
    }
}

// MARK: - Permissions

@Test func anAllowedPermissionRoundTripsThroughStdin() async throws {
    let recorded = try RecordedSession.claudePermission()
    try await withEndToEnd { e2e in
        try e2e.claude.on(FakeCLI.userTurn, reply: recorded.untilAsking)
        try e2e.claude.on(FakeCLI.permissionAnswer, reply: recorded.afterAnswer)
        let chat = try await e2e.newChat()

        await chat.send(text: "Use a ferramenta Write para criar prova.txt com o texto ok.")
        await settle(within: processPatience) { chat.pending != nil }
        #expect(chat.pending?.toolName == "Write")
        #expect(e2e.workspace.indicator(for: chat.sessionID) == .waiting)

        await chat.resolve(allow: true)
        await settle(within: processPatience) { !chat.isBusy }

        let answer = try #require(e2e.claude.received.last)
        #expect(answer.contains(#""request_id":"a7c8532d-65be-4a74-8a3f-bd2f485e9a61""#))
        #expect(answer.contains(#""behavior":"allow""#))
        #expect(chat.pending == nil)
        #expect(chat.lines.last?.role == .assistant)
        #expect(chat.lines.last?.text == "Arquivo `prova.txt` criado com o conteúdo \"ok\".")
    }
}

@Test func aDeniedPermissionReachesTheCLI() async throws {
    let recorded = try RecordedSession.claudePermission()
    try await withEndToEnd { e2e in
        try e2e.claude.on(FakeCLI.userTurn, reply: recorded.untilAsking)
        try e2e.claude.on(FakeCLI.permissionAnswer, reply: [try #require(recorded.afterAnswer.last)])
        let chat = try await e2e.newChat()

        await chat.send(text: "Use a ferramenta Write para criar prova.txt com o texto ok.")
        await settle(within: processPatience) { chat.pending != nil }
        await chat.resolve(allow: false)
        await settle(within: processPatience) { !chat.isBusy }

        let answer = try #require(e2e.claude.received.last)
        #expect(answer.contains(#""behavior":"deny""#))
    }
}

// MARK: - Knobs

@Test func thePermissionModeChangesInPlaceWithoutARelaunch() async throws {
    try await withEndToEnd { e2e in
        let chat = try await e2e.newChat()

        await chat.choose(knob: "mode", value: "acceptEdits")
        await settle(within: processPatience) { !e2e.claude.received.isEmpty }

        let request = try #require(e2e.claude.received.first)
        #expect(request.contains(#""subtype":"set_permission_mode""#))
        #expect(request.contains(#""mode":"acceptEdits""#))
        #expect(e2e.claude.launches.count == 1)
        #expect(chat.knob("mode")?.currentValue == "acceptEdits")
    }
}

@Test func theModelRelaunchesTheCLIWithTheFlag() async throws {
    try await withEndToEnd { e2e in
        let chat = try await e2e.newChat()

        await chat.choose(knob: "model", value: "sonnet")
        await settle(within: processPatience) { e2e.claude.launches.count == 2 }

        #expect(e2e.claude.launches.count == 2)
        #expect(argument(after: "--model", in: e2e.claude.launches.last) == "sonnet")
        #expect(argument(after: "--resume", in: e2e.claude.launches.last) == nil)
        #expect(chat.isLive)
    }
}

@Test func aRelaunchAfterAReplyResumesTheSameCLISession() async throws {
    try await withEndToEnd { e2e in
        try e2e.claude.on(FakeCLI.userTurn, reply: RecordedSession.claude("hello"))
        let chat = try await e2e.newChat()
        await chat.send(text: "Diga apenas OK e nada mais.")
        await settle(within: processPatience) { !chat.isBusy }

        await chat.choose(knob: "model", value: "sonnet")
        await settle(within: processPatience) { e2e.claude.launches.count == 2 }

        let relaunch = e2e.claude.launches.last
        #expect(argument(after: "--resume", in: relaunch) == recordedSessionID)
        #expect(argument(after: "--model", in: relaunch) == "sonnet")
    }
}

@Test func theEffortRelaunchesTheCLIWithTheFlag() async throws {
    try await withEndToEnd { e2e in
        let chat = try await e2e.newChat()

        await chat.choose(knob: "effort", value: "high")
        await settle(within: processPatience) { e2e.claude.launches.count == 2 }

        #expect(chat.knob("effort")?.currentValue == "high")
        #expect(argument(after: "--effort", in: e2e.claude.launches.last) == "high")
        #expect(chat.isLive)
    }
}

// MARK: - Failure

@Test func aCLIThatDiesMidTurnSaysWhyAndGoesCold() async throws {
    try await withEndToEnd { e2e in
        try e2e.claude.on(FakeCLI.userTurn, exit: 1, stderr: "Error: invalid API key")
        let chat = try await e2e.newChat()

        await chat.send(text: "hello")
        await settle(within: processPatience) { !chat.isLive }

        #expect(chat.isBusy == false)
        #expect(chat.turnStartedAt == nil)
        #expect(chat.status == "encerrada: o CLI saiu com código 1: Error: invalid API key")
        #expect(notices(chat) == ["a sessão caiu: o CLI saiu com código 1: Error: invalid API key"])
    }
}

// MARK: - Across launches of the app

@Test func aConversationSurvivesARelaunchAndResumesTheCLISession() async throws {
    try await withEndToEnd { e2e in
        try e2e.claude.on(FakeCLI.userTurn, reply: RecordedSession.claude("hello"))
        try e2e.claude.on(FakeCLI.userTurn, reply: RecordedSession.claude("hello"))
        let first = try await e2e.newChat()
        await first.send(text: "Diga apenas OK e nada mais.")
        await settle(within: processPatience) { !first.isBusy }
        await e2e.workspace.stopAll()

        let reopened = e2e.relaunched()
        await reopened.refresh()
        let id = try #require(reopened.summaries.first?.id)
        #expect(id == first.sessionID)
        await reopened.select(id)
        let restored = try #require(reopened.active)
        #expect(restored.lines.map(\.text) == ["Diga apenas OK e nada mais.", "OK"])
        #expect(restored.isLive == false)

        await restored.send(text: "De novo.")
        await settle(within: processPatience) { !restored.isBusy }

        #expect(e2e.claude.launches.count == 2)
        #expect(argument(after: "--resume", in: e2e.claude.launches.last) == recordedSessionID)
        #expect(restored.lines.map(\.text) == ["Diga apenas OK e nada mais.", "OK", "De novo.", "OK"])
    }
}
