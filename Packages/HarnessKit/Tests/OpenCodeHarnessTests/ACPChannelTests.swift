import Testing
import Foundation
import HarnessCore
import HarnessTestSupport
@testable import OpenCodeHarness

private func launch(_ script: String) -> ProcessTransport.Launch {
    ProcessTransport.Launch(
        executable: "/bin/sh",
        arguments: ["-c", script],
        workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
    )
}

private let idOf = #"id=$(printf '%s' "$l" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')"#

private let echoingAgent = """
while IFS= read -r l; do
  case "$l" in
    *'"method":"boom"'*)
      \(idOf)
      printf '{"jsonrpc":"2.0","id":%s,"error":{"code":-32602,"message":"Invalid params"}}\\n' "$id"
      ;;
    *'"method":"quiet"'*) ;;
    *'"id"'*)
      \(idOf)
      printf '{"jsonrpc":"2.0","id":%s,"result":{"ok":true}}\\n' "$id"
      ;;
    *)

      printf '{"jsonrpc":"2.0","method":"saw","params":{"line":%s}}\\n' "$(printf '%s' "$l" | sed 's/"/\\\\"/g; s/^/"/; s/$/"/')"
      ;;
  esac
done
"""

@Test func sendCorrelatesTheResponseByRequestID() async throws {
    let channel = ACPChannel(transport: ProcessTransport())
    let stream = try await channel.start(launch(echoingAgent))
    let drain = Task { for try await _ in stream {} }
    defer { drain.cancel() }
    let result = try await withTimeout(seconds: 5) { try await channel.send("anything") }
    #expect(result["ok"]?.boolValue == true)
    await channel.stop()
}

@Test func twoRequestsInFlightGetTheirOwnResponses() async throws {
    let channel = ACPChannel(transport: ProcessTransport())
    let stream = try await channel.start(launch(echoingAgent))
    let drain = Task { for try await _ in stream {} }
    defer { drain.cancel() }
    let both = try await withTimeout(seconds: 5) {
        async let first = channel.send("one")
        async let second = channel.send("two")
        return try await [first, second]
    }
    #expect(both.count == 2)
    await channel.stop()
}

@Test func anErrorResponseSurfacesAsAThrow() async throws {
    let channel = ACPChannel(transport: ProcessTransport())
    let stream = try await channel.start(launch(echoingAgent))
    let drain = Task { for try await _ in stream {} }
    defer { drain.cancel() }
    await #expect(throws: ACPChannel.ChannelError.requestFailed(
        code: -32602, message: "Invalid params")) {
        try await withTimeout(seconds: 5) { try await channel.send("boom") }
    }
    await channel.stop()
}

@Test func aRequestThatIsNeverAnsweredTimesOut() async throws {
    let channel = ACPChannel(transport: ProcessTransport(), requestTimeout: .milliseconds(120))
    let stream = try await channel.start(launch(echoingAgent))
    let drain = Task { for try await _ in stream {} }
    defer { drain.cancel() }
    await #expect(throws: ACPChannel.ChannelError.timedOut) {
        try await withTimeout(seconds: 5) { try await channel.send("quiet") }
    }
    await channel.stop()
}

@Test func aNotificationReachesTheAgentWithoutAnID() async throws {
    let channel = ACPChannel(transport: ProcessTransport())
    let stream = try await channel.start(launch(echoingAgent))
    try await channel.notify("session/cancel", .object(["sessionId": .string("ses_1")]))

    let seen: String? = try await withTimeout(seconds: 5) {
        for try await output in stream {
            if case .notification(let method, let params) = output, method == "saw" {
                return params["line"]?.stringValue
            }
        }
        return nil
    }
    let line = try #require(seen)
    #expect(line.contains(#""method":"session/cancel""#))

    #expect(!line.contains(#""id""#), "a notificação levou id — o agente vai esperar resposta")
    await channel.stop()
}

private let askingAgent = #"""
printf '{"jsonrpc":"2.0","id":0,"method":"session/request_permission","params":{"toolCall":{"title":"echo oi"}}}\n'
cat > /dev/null
"""#

@Test func anInboundRequestSurfacesAndCanBeAnswered() async throws {
    let channel = ACPChannel(transport: ProcessTransport())
    let stream = try await channel.start(launch(askingAgent))

    let asked: JSONValue? = try await withTimeout(seconds: 5) {
        for try await output in stream {
            if case .request(let id, let method, _) = output,
               method == "session/request_permission" {
                return id
            }
        }
        return nil
    }
    let id = try #require(asked)
    try await channel.respond(to: id, with: .object(["outcome": .string("selected")]))

    await #expect(throws: ACPChannel.ChannelError.unknownRequest) {
        try await channel.respond(to: id, with: .object([:]))
    }
    await channel.stop()
}

@Test func sendOnAChannelThatNeverStartedIsRefused() async throws {
    let channel = ACPChannel(transport: ProcessTransport())
    await #expect(throws: ACPChannel.ChannelError.notStarted) {
        try await channel.send("session/prompt")
    }
}

@Test func sendAfterStopIsRefused() async throws {
    let channel = ACPChannel(transport: ProcessTransport())
    _ = try await channel.start(launch(echoingAgent))
    await channel.stop()
    await #expect(throws: ACPChannel.ChannelError.channelClosed) {
        try await channel.send("session/prompt")
    }
}
