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

/// Devolve um control_response de sucesso para cada control_request que chegar,
/// ecoando o request_id — e também o `subtype` pedido, dentro do payload.
///
/// Ecoar o subtype não é enfeite: sem ele, dois requests em voo recebem
/// payloads idênticos, e um teste de correlação passaria igual se as duas
/// respostas fossem trocadas entre si. Linhas que não são de controle são
/// ignoradas.
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
        async let second = channel.send(.setPermissionMode("acceptEdits"))
        return try await [first, second]
    }
    #expect(results.count == 2)
    #expect(results.allSatisfy { $0["ok"] == .bool(true) })
    // Cada um recebeu a resposta do *seu* pedido, e não a do outro. A ordem em
    // que os dois chegaram ao stdin não importa: a correlação é por
    // request_id, então este par de expectativas vale de qualquer jeito — e
    // falha se as respostas forem entregues trocadas.
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
    // Um harness que lê e não responde. Sem prazo, send() esperaria para sempre.
    let channel = ControlChannel(transport: ProcessTransport(),
                                 requestTimeout: .milliseconds(80))
    let stream = try await channel.start(launch("cat > /dev/null"))
    let drain = Task { for try await _ in stream {} }
    defer { drain.cancel() }

    await #expect(throws: ControlChannel.ChannelError.timedOut) {
        _ = try await channel.send(.interrupt)
    }
    await channel.stop()
}

/// Controller ruling: quem espera por uma resposta quando o harness morre
/// precisa saber que o canal fechou. `.notStarted` aqui seria o oposto do que
/// aconteceu — um request que chegou a ser escrito no stdin de um processo vivo
/// não pode falhar dizendo que o canal nunca subiu.
@Test func aPendingRequestFailsWithChannelClosedWhenTheHarnessExits() async throws {
    // Lê o request e sai sem responder: o fluxo termina com um pedido em voo.
    let channel = ControlChannel(transport: ProcessTransport())
    let stream = try await channel.start(launch("read -r l; exit 0"))
    let drain = Task { for try await _ in stream {} }
    defer { drain.cancel() }

    await #expect(throws: ControlChannel.ChannelError.channelClosed) {
        _ = try await withTimeout(seconds: 3) { try await channel.send(.interrupt) }
    }
    await channel.stop()
}

/// Abandonar o fluxo cancela a bomba interna, mas **não** mata o harness: o
/// filho segue vivo, agora com um stdout que ninguém lê. Quem é dono do canal
/// tem que chamar `stop()`. Este teste fixa esse contrato — se um dia o
/// abandono passar a matar o filho sozinho, ele avisa.
@Test func abandoningTheStreamLeavesTheChildForStopToReclaim() async throws {
    let transport = ProcessTransport()
    let channel = ControlChannel(transport: transport)
    let stream = try await channel.start(launch(#"printf '{"type":"assistant"}\n'; sleep 30"#))

    for try await _ in stream { break }

    #expect(await transport.terminationStatus == nil)
    await channel.stop()
    #expect(await transport.terminationStatus != nil)
}
