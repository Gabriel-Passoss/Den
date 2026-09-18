import Testing
import Foundation
import HarnessCore
import HarnessTestSupport
@testable import ClaudeHarness

private func launch(_ script: String) -> ProcessTransport.Launch {
    ProcessTransport.Launch(
        executable: "/bin/sh",
        arguments: ["-c", script],
        workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
    )
}

private let echoingResponder = #"""
while IFS= read -r l; do
  case "$l" in
    *'"type":"control_request"'*)
      id=$(printf '%s' "$l" | sed -n 's/.*"request_id":"\([^"]*\)".*/\1/p')
      sub=$(printf '%s' "$l" | sed -n 's/.*"subtype":"\([^"]*\)".*/\1/p')
      printf '{"type":"control_response","response":{"subtype":"success","request_id":"%s","response":{"ok":true,"echo":"%s"}}}\n' "$id" "$sub"
      ;;
  esac
done
"""#

private let askingHarnessForWrite = #"""
printf '{"type":"control_request","request_id":"ask-dup","request":{"subtype":"can_use_tool","tool_name":"Write","input":{}}}\n'
cat > /dev/null
"""#

@Test func conversationLinesReachTheConsumer() async throws {
    let channel = ControlChannel(transport: ProcessTransport())
    let stream = try await channel.start(launch(#"printf '{"type":"assistant"}\n{"type":"result"}\n'"#))

    var seen: [String] = []
    for try await output in stream {
        if case .conversation(let data) = output {
            seen.append(String(decoding: data, as: UTF8.self))
        }
    }
    #expect(seen == [#"{"type":"assistant"}"#, #"{"type":"result"}"#])
}

@Test func aControlResponseIsNotDeliveredAsConversation() async throws {
    let channel = ControlChannel(transport: ProcessTransport())
    let line = #"{"type":"control_response","response":{"subtype":"success","request_id":"x","response":{}}}"#
    let stream = try await channel.start(launch("printf '\(line)\\n{\"type\":\"result\"}\\n'"))

    var conversation = 0
    for try await output in stream {
        if case .conversation = output { conversation += 1 }
    }
    #expect(conversation == 1)
}

@Test func sendCorrelatesTheResponseByRequestID() async throws {
    let channel = ControlChannel(transport: ProcessTransport())
    let stream = try await channel.start(launch(echoingResponder))
    let drain = Task { for try await _ in stream {} }
    defer { drain.cancel() }

    let payload = try await withTimeout(seconds: 3) {
        try await channel.send(.interrupt)
    }
    #expect(payload["ok"] == .bool(true))
    await channel.stop()
}

@Test func twoRequestsInFlightGetTheirOwnResponses() async throws {
    let channel = ControlChannel(transport: ProcessTransport())
    let stream = try await channel.start(launch(echoingResponder))
    let drain = Task { for try await _ in stream {} }
    defer { drain.cancel() }

    let results = try await withTimeout(seconds: 3) {
        async let first = channel.send(.interrupt)
        async let second = channel.send(.setPermissionMode(.acceptEdits))
        return try await [first, second]
    }
    #expect(results.count == 2)
    #expect(results.allSatisfy { $0["ok"] == .bool(true) })

    #expect(results[0]["echo"] == .string("interrupt"))
    #expect(results[1]["echo"] == .string("set_permission_mode"))
    await channel.stop()
}

@Test func anErrorResponseSurfacesAsAThrow() async throws {
    let responder = #"""
    while IFS= read -r l; do
      id=$(printf '%s' "$l" | sed -n 's/.*"request_id":"\([^"]*\)".*/\1/p')
      printf '{"type":"control_response","response":{"subtype":"error","request_id":"%s","error":"recusado"}}\n' "$id"
    done
    """#
    let channel = ControlChannel(transport: ProcessTransport())
    let stream = try await channel.start(launch(responder))
    let drain = Task { for try await _ in stream {} }
    defer { drain.cancel() }

    await #expect(throws: ControlChannel.ChannelError.requestFailed("recusado")) {
        _ = try await withTimeout(seconds: 3) { try await channel.send(.interrupt) }
    }
    await channel.stop()
}

@Test func aRequestThatIsNeverAnsweredTimesOut() async throws {

    let channel = ControlChannel(transport: ProcessTransport(),
                                 requestTimeout: .milliseconds(80))
    let stream = try await channel.start(launch("cat > /dev/null"))
    let drain = Task { for try await _ in stream {} }
    defer { drain.cancel() }

    await #expect(throws: ControlChannel.ChannelError.timedOut) {
        _ = try await withTimeout(seconds: 3) { try await channel.send(.interrupt) }
    }
    await channel.stop()
}

@Test func aPendingRequestFailsWithChannelClosedWhenTheHarnessExits() async throws {

    let channel = ControlChannel(transport: ProcessTransport())
    let stream = try await channel.start(launch("read -r l; exit 0"))
    let drain = Task { for try await _ in stream {} }
    defer { drain.cancel() }

    await #expect(throws: ControlChannel.ChannelError.channelClosed) {
        _ = try await withTimeout(seconds: 3) { try await channel.send(.interrupt) }
    }
    await channel.stop()
}

@Test func abandoningTheStreamLeavesTheChildForStopToReclaim() async throws {
    let transport = ProcessTransport()
    let channel = ControlChannel(transport: transport)
    let stream = try await channel.start(launch(#"printf '{"type":"assistant"}\n'; sleep 30"#))

    for try await _ in stream { break }

    #expect(await transport.terminationStatus == nil)
    await channel.stop()
    #expect(await transport.terminationStatus != nil)
}

@Test func sendAfterStopFailsWithChannelClosed() async throws {
    let channel = ControlChannel(transport: ProcessTransport())
    let stream = try await channel.start(launch(echoingResponder))
    let drain = Task { for try await _ in stream {} }
    defer { drain.cancel() }

    await channel.stop()

    await #expect(throws: ControlChannel.ChannelError.channelClosed) {
        _ = try await withTimeout(seconds: 3) { try await channel.send(.interrupt) }
    }
}

@Test func sendBeforeStartFailsWithNotStarted() async throws {
    let channel = ControlChannel(transport: ProcessTransport())
    await #expect(throws: ControlChannel.ChannelError.notStarted) {
        _ = try await channel.send(.interrupt)
    }
}

private actor SingleSignal {
    private var fired = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func fire() {
        guard !fired else { return }
        fired = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }

    func wait() async {
        if fired { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

@Test func aPendingSendStillResolvesAfterEndInputClosesStdin() async throws {
    let responder = #"""
    IFS= read -r l
    id=$(printf '%s' "$l" | sed -n 's/.*"request_id":"\([^"]*\)".*/\1/p')
    printf '{"type":"ack"}\n'
    cat > /dev/null
    printf '{"type":"control_response","response":{"subtype":"success","request_id":"%s","response":{"ok":true}}}\n' "$id"
    """#
    let channel = ControlChannel(transport: ProcessTransport())
    let stream = try await channel.start(launch(responder))

    let ackSeen = SingleSignal()
    let drain = Task {
        for try await output in stream {
            if case .conversation = output { await ackSeen.fire() }
        }
    }
    defer { drain.cancel() }

    let sendTask = Task { try await channel.send(.interrupt) }

    try await withTimeout(seconds: 3) { await ackSeen.wait() }
    await channel.endInput()

    let payload = try await withTimeout(seconds: 3) { try await sendTask.value }
    #expect(payload["ok"] == .bool(true))
}

@Test func anUnknownControlRequestIsRefusedSoTheHarnessUnblocks() async throws {
    let blockingHarness = #"""
    printf '{"type":"control_request","request_id":"u-1","request":{"subtype":"coisa_nova","x":1}}\n'
    IFS= read -r resposta
    sub=$(printf '%s' "$resposta" | sed -n 's/.*"subtype":"\([^"]*\)".*/\1/p')
    id=$(printf '%s' "$resposta" | sed -n 's/.*"request_id":"\([^"]*\)".*/\1/p')
    printf '{"type":"result","destravou":"%s","para":"%s"}\n' "$sub" "$id"
    """#
    let channel = ControlChannel(transport: ProcessTransport())
    let stream = try await channel.start(launch(blockingHarness))

    let (seen, unblocked) = try await withTimeout(seconds: 3) {
        () async throws -> (UnrecognizedControl?, JSONValue?) in
        var seen: UnrecognizedControl?
        var unblocked: JSONValue?
        for try await output in stream {
            switch output {
            case .unrecognizedControl(let u): seen = u
            case .conversation(let data):
                unblocked = try? JSONDecoder().decode(JSONValue.self, from: data)
            case .permissionRequest:
                Issue.record("um subtipo desconhecido não é pedido de permissão")
            }
        }
        return (seen, unblocked)
    }

    let u = try #require(seen, "o consumidor tem que ver o quadro que recusamos")
    #expect(u.requestID == "u-1")
    #expect(u.wasAnswered)
    #expect(u.automaticReply == ControlChannel.refusalMessage)

    #expect(u.raw["request"]?["subtype"] == .string("coisa_nova"))

    #expect(unblocked?["destravou"] == .string("error"))
    #expect(unblocked?["para"] == .string("u-1"))
    await channel.stop()
}

@Test func anIDLessPermissionRequestIsLoggedRatherThanOfferedForApproval() async throws {
    let harness = #"""
    printf '{"type":"control_request","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{}}}\n'
    printf '{"type":"result"}\n'
    """#
    let channel = ControlChannel(transport: ProcessTransport())
    let stream = try await channel.start(launch(harness))

    let seen = try await withTimeout(seconds: 3) { () async throws -> UnrecognizedControl? in
        var seen: UnrecognizedControl?
        for try await output in stream {
            switch output {
            case .unrecognizedControl(let u): seen = u
            case .permissionRequest:
                Issue.record("um pedido sem id não é respondível — não pode virar diálogo")
            case .conversation: break
            }
        }
        return seen
    }
    let u = try #require(seen)
    #expect(u.requestID == nil)
    #expect(!u.wasAnswered)
    #expect(u.raw["request"]?["tool_name"] == .string("Bash"))
}

@Test func respondingTwiceToTheSameRequestIsRefusedTheSecondTime() async throws {
    let channel = ControlChannel(transport: ProcessTransport())
    let stream = try await channel.start(launch(askingHarnessForWrite))

    try await withTimeout(seconds: 3) {
        for try await output in stream {
            guard case .permissionRequest(let r) = output else { continue }
            try await channel.respond(to: r.id, with: .allow(updatedInput: nil))
            await #expect(throws: ControlChannel.ChannelError.unknownRequest(r.id)) {
                try await channel.respond(to: r.id, with: .deny(message: "tudo não", interrupt: true))
            }

            return
        }
        Issue.record("o harness falso nunca pediu permissão")
    }
    await channel.stop()
}

@Test func respondingToAnIDTheChannelNeverDeliveredIsRefused() async throws {
    let channel = ControlChannel(transport: ProcessTransport())
    let stream = try await channel.start(launch("cat > /dev/null"))
    let drain = Task { for try await _ in stream {} }
    defer { drain.cancel() }

    await #expect(throws: ControlChannel.ChannelError.unknownRequest("inventado")) {
        try await withTimeout(seconds: 3) {
            try await channel.respond(to: "inventado", with: .allow(updatedInput: nil))
        }
    }
    await channel.stop()
}

private let harnessThatClosesItsStdinAndStaysAlive = #"""
exec 0<&-
printf '{"type":"control_request","request_id":"p-1","request":{"subtype":"can_use_tool","tool_name":"Write","input":{}}}\n'
printf '{"type":"fechei"}\n'
sleep 30
"""#

@Test func respondFailsWithChannelClosedWhenTheWriteHitsADeadPipe() async throws {
    let channel = ControlChannel(transport: ProcessTransport())
    let stream = try await channel.start(launch(harnessThatClosesItsStdinAndStaysAlive))

    try await withTimeout(seconds: 3) {
        var requestID: String?
        for try await output in stream {
            switch output {
            case .permissionRequest(let r):
                requestID = r.id
            case .conversation(let data):

                guard String(decoding: data, as: UTF8.self).contains("fechei") else { continue }
                let id = try #require(requestID)
                await #expect(throws: ControlChannel.ChannelError.channelClosed) {
                    try await channel.respond(to: id, with: .allow(updatedInput: nil))
                }
                return
            case .unrecognizedControl:
                Issue.record("esperava um pedido de permissão bem formado")
            }
        }
        Issue.record("o harness falso nunca anunciou que fechou o stdin")
    }
    await channel.stop()
}

@Test func sendFailsWithChannelClosedWhenTheWriteHitsADeadPipe() async throws {
    let channel = ControlChannel(transport: ProcessTransport())
    let stream = try await channel.start(launch(harnessThatClosesItsStdinAndStaysAlive))

    try await withTimeout(seconds: 3) {
        for try await output in stream {
            guard case .conversation(let data) = output,
                  String(decoding: data, as: UTF8.self).contains("fechei")
            else { continue }
            await #expect(throws: ControlChannel.ChannelError.channelClosed) {
                _ = try await channel.send(.interrupt)
            }
            return
        }
        Issue.record("o harness falso nunca anunciou que fechou o stdin")
    }
    await channel.stop()
}
