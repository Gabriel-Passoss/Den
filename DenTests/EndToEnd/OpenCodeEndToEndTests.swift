import Testing
import Foundation
import HarnessCore
@testable import Den

private let recordedSessionID = "ses_f36efb87cffeg77EZ6KnLXjEmd"

private let recordedConfigOptions = #"""
[{"id":"model","name":"Model","category":"model","type":"select","currentValue":"opencode/big-pickle","options":[{"value":"openai/gpt-5.4","name":"OpenAI/GPT-5.4"},{"value":"opencode/big-pickle","name":"OpenCode Zen/Big Pickle"}]},{"id":"mode","name":"Session Mode","category":"mode","type":"select","currentValue":"build","options":[{"value":"build","name":"build"},{"value":"plan","name":"plan"}]}]
"""#

private func response(_ result: String) -> String {
    #"{"jsonrpc":"2.0","id":__ID__,"result":\#(result)}"#
}

private func handshake(_ cli: FakeCLI, opening method: String = "session/new") throws {
    try cli.on(FakeCLI.request("initialize"), reply: [
        response(#"{"protocolVersion":1,"agentCapabilities":{"loadSession":true}}"#),
    ])
    try cli.on(FakeCLI.request(method), reply: [
        response(#"{"sessionId":"\#(recordedSessionID)","configOptions":\#(recordedConfigOptions)}"#),
    ])
}

private func recordedTurnCutAtThePermissionAsk() throws
    -> (untilAsking: [String], afterAnswer: [String]) {
    let lines = try RecordedSession.openCode("turn-with-permission")
    let asking = try #require(lines.firstIndex { $0.contains("session/request_permission") })
    let recordedClosing = try #require(lines.last)
    let closing = recordedClosing.replacingOccurrences(of: #""id":3,"#, with: #""id":__ID__,"#)
    try #require(closing != recordedClosing)
    return (Array(lines[...asking]), Array(lines[(asking + 1)..<(lines.count - 1)]) + [closing])
}

private func sent(_ cli: FakeCLI, _ method: String) -> [String] {
    cli.received.filter { $0.contains(FakeCLI.request(method)) }
}

@Test func anOpenCodeConversationHandshakesOverACP() async throws {
    try await withEndToEnd { e2e in
        try handshake(e2e.openCode)
        let chat = try await e2e.newChat(on: openCodeID)

        #expect(e2e.openCode.launches.first?.arguments
                == ["acp", "--cwd", e2e.project.path])
        #expect(sent(e2e.openCode, "initialize").count == 1)
        #expect(sent(e2e.openCode, "session/new").first?.contains(e2e.project.path) == true)
        #expect(chat.knobs.map(\.name) == ["Modelo", "Modo"])
        await settle(within: processPatience) { chat.model == "opencode/big-pickle" }
    }
}

@Test func anOpenCodeThatDiesWhileStartingSaysWhy() async throws {
    try await withEndToEnd { e2e in
        try e2e.openCode.on(FakeCLI.request("initialize"), exit: 1,
                            stderr: "Error: not logged in")
        await e2e.workspace.newSession(harness: openCodeID)
        let chat = try #require(e2e.workspace.active)

        #expect(chat.isLive == false)
        #expect(chat.lines.filter { $0.role == .notice }.map(\.text) == [
            "não consegui subir o harness: o CLI saiu com código 1: Error: not logged in",
        ])
    }
}

@Test func aRecordedTurnWithAPermissionPlaysThroughACP() async throws {
    let recorded = try recordedTurnCutAtThePermissionAsk()
    try await withEndToEnd { e2e in
        try handshake(e2e.openCode)
        try e2e.openCode.on(FakeCLI.request("session/prompt"), reply: recorded.untilAsking)
        try e2e.openCode.on(FakeCLI.answer, reply: recorded.afterAnswer)
        let chat = try await e2e.newChat(on: openCodeID)

        await chat.send(text: "Rode echo oi no bash.")
        await settle(within: processPatience) { chat.pending != nil }
        #expect(chat.pending?.toolName == "echo oi")
        #expect(chat.pending?.options.map(\.label) == ["Permitir", "Sempre permitir", "Negar"])

        await chat.resolve(allow: true)
        await settle(within: processPatience) { !chat.isBusy }

        let prompt = try #require(sent(e2e.openCode, "session/prompt").first)
        #expect(prompt.contains(#""text":"Rode echo oi no bash.""#))
        let permission = try #require(e2e.openCode.received.last)
        #expect(permission.contains(#""optionId":"once""#))
        #expect(chat.lines.first?.role == .user)
        #expect(chat.lines.last?.role == .assistant)
        #expect(chat.lines.last?.text == "oi")
        #expect(chat.lines.contains { $0.role == .tool })
    }
}

@Test func anOpenCodeKnobChangesThroughSetConfigOption() async throws {
    let planned = recordedConfigOptions
        .replacingOccurrences(of: #""currentValue":"build""#, with: #""currentValue":"plan""#)
    try await withEndToEnd { e2e in
        try handshake(e2e.openCode)
        try e2e.openCode.on(FakeCLI.request("session/set_config_option"), reply: [
            response(#"{"configOptions":\#(planned)}"#),
        ])
        let chat = try await e2e.newChat(on: openCodeID)

        await chat.choose(knob: "mode", value: "plan")

        let change = try #require(sent(e2e.openCode, "session/set_config_option").first)
        #expect(change.contains(#""configId":"mode""#))
        #expect(change.contains(#""value":"plan""#))
        #expect(chat.knob("mode")?.currentValue == "plan")
        #expect(e2e.openCode.launches.count == 1)
    }
}

@Test func aRestoredOpenCodeConversationLoadsItsSession() async throws {
    let recorded = try recordedTurnCutAtThePermissionAsk()
    try await withEndToEnd { e2e in
        try handshake(e2e.openCode)
        try e2e.openCode.on(FakeCLI.request("session/prompt"),
                            reply: [try #require(recorded.untilAsking.first),
                                    try #require(recorded.afterAnswer.last)])
        try handshake(e2e.openCode, opening: "session/load")
        let first = try await e2e.newChat(on: openCodeID)
        await first.send(text: "Oi")
        await settle(within: processPatience) { !first.isBusy }
        await e2e.workspace.stopAll()

        let reopened = e2e.relaunched()
        await reopened.refresh()
        await reopened.select(first.sessionID)
        let restored = try #require(reopened.active)
        await restored.start()

        let load = try #require(sent(e2e.openCode, "session/load").first)
        #expect(load.contains(#""sessionId":"\#(recordedSessionID)""#))
        #expect(restored.isLive)
    }
}

@Test func switchingToOpenCodeHandsTheConversationOver() async throws {
    try await withEndToEnd { e2e in
        try e2e.claude.on(FakeCLI.userTurn, reply: RecordedSession.claude("hello"))
        try handshake(e2e.openCode)
        let chat = try await e2e.newChat()
        await chat.send(text: "Diga apenas OK e nada mais.")
        await settle(within: processPatience) { !chat.isBusy }

        await chat.switchHarness(to: openCodeID)
        await chat.send(text: "E agora?")
        await settle(within: processPatience) { !sent(e2e.openCode, "session/prompt").isEmpty }

        #expect(chat.harness == openCodeID)
        #expect(chat.harnessName == "OpenCode")
        let prompt = try #require(sent(e2e.openCode, "session/prompt").first)
        #expect(prompt.contains("Diga apenas OK e nada mais."))
        #expect(prompt.contains("E agora?"))

        let listed = e2e.relaunched()
        await refresh(listed) { listed.summaries.first?.harnesses == [claudeCodeID, openCodeID] }
        #expect(listed.summaries.first?.harnesses == [claudeCodeID, openCodeID])
    }
}

@Test func eachReplyKeepsTheHarnessThatWroteItAcrossAHandoffAndARelaunch() async throws {
    let recorded = try recordedTurnCutAtThePermissionAsk()
    try await withEndToEnd { e2e in
        try e2e.claude.on(FakeCLI.userTurn, reply: RecordedSession.claude("hello"))
        try handshake(e2e.openCode)
        try e2e.openCode.on(FakeCLI.request("session/prompt"), reply: recorded.untilAsking)
        try e2e.openCode.on(FakeCLI.answer, reply: recorded.afterAnswer)
        let chat = try await e2e.newChat()
        await chat.send(text: "Diga apenas OK e nada mais.")
        await settle(within: processPatience) { !chat.isBusy }

        await chat.switchHarness(to: openCodeID)
        await chat.send(text: "Rode echo oi no bash.")
        await settle(within: processPatience) { chat.pending != nil }
        await chat.resolve(allow: true)
        await settle(within: processPatience) { !chat.isBusy }

        let authors = { (lines: [ChatLine]) in
            lines.filter { $0.role == .assistant }.map { "\($0.text)@\($0.harness?.rawValue ?? "?")" }
        }
        #expect(authors(chat.lines) == ["OK@claude-code", "I'll run the command.@opencode", "oi@opencode"])
        #expect(chat.lines.filter { $0.role == .tool }.allSatisfy { $0.harness == openCodeID })
        let headers = ChatView.turnStarts(in: chat.blocks)
        let authorsOfHeaders = chat.blocks.filter { headers.contains($0.id) }.map(ChatView.harness(of:))
        #expect(authorsOfHeaders == [claudeCodeID, openCodeID])

        await e2e.workspace.stopAll()
        let reopened = e2e.relaunched()
        await refresh(reopened) { reopened.summaries.first?.harnesses == [claudeCodeID, openCodeID] }
        await reopened.select(chat.sessionID)
        let restored = try #require(reopened.active)

        #expect(restored.harness == openCodeID)
        #expect(authors(restored.lines) == ["OK@claude-code", "I'll run the command.@opencode", "oi@opencode"])
    }
}
