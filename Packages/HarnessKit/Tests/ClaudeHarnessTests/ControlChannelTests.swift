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

    // O `withTimeout` não é o que está sendo testado — é a rede. Um `send`
    // pelado aqui significa que uma regressão no prazo trava a suíte inteira em
    // vez de falhar; e `TimedOut` não é `.timedOut`, então a rede nunca pode
    // ser confundida com um teste passando.
    await #expect(throws: ControlChannel.ChannelError.timedOut) {
        _ = try await withTimeout(seconds: 3) { try await channel.send(.interrupt) }
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

/// Depois de `stop()`, o canal tem que dizer que fechou — e dizer isso com o
/// seu próprio vocabulário. Sem isso, o mirror do stdin continua preenchido, a
/// escrita bate num filho já morto, e o chamador recebe um `NSError` de EPIPE:
/// um erro de Foundation vazando por uma API que promete `ChannelError`.
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

/// E antes de `start(_:)` continua sendo `.notStarted` — os dois estados são
/// distintos e o chamador merece saber qual deles encontrou.
@Test func sendBeforeStartFailsWithNotStarted() async throws {
    let channel = ControlChannel(transport: ProcessTransport())
    await #expect(throws: ControlChannel.ChannelError.notStarted) {
        _ = try await channel.send(.interrupt)
    }
}

/// Sinaliza uma vez só, para quem espera. Existe para este teste: precisamos
/// saber que o harness falso já leu o request antes de fechar o stdin, sem
/// depender da ordem de agendamento entre duas tasks — só de uma linha que o
/// próprio harness escreve depois de ler.
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

/// Fixa o argumento por trás da correção ao controller ruling: fechar o stdin
/// não impede o harness de responder pelo stdout — `endInput()` fecha só o
/// lado da escrita, e a leitura do stdout continua entregando linhas à bomba
/// normalmente. Por isso `endInput()` marca `liveness = .closed` mas **não**
/// chama `failAllPending`: um request que já estava pendente pode muito bem
/// ganhar sua resposta legítima depois do stdin fechar, e falhá-lo ali
/// quebraria um caminho que funciona para "corrigir" um problema que não
/// existe. Antes deste teste, essa garantia só existia na cabeça de quem
/// revisou o código — nada na suíte reclamava se alguém reintroduzisse
/// `failAllPending` dentro de `endInput()`.
///
/// O harness falso: lê o request, ecoa um `ack` de conversa (prova, do lado
/// de fora, que já leu antes de qualquer stdin fechar), drena o próprio stdin
/// até o EOF que `endInput()` provoca, e só então escreve o
/// `control_response` no stdout.
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

    // Só fecha o stdin depois de ver a prova de que o harness já leu o
    // request — sem isso, `endInput()` poderia vencer a corrida contra a
    // escrita de `send(_:)` e fechar um canal que `liveness` ainda não viu
    // ninguém usar.
    try await withTimeout(seconds: 3) { await ackSeen.wait() }
    await channel.endInput()

    let payload = try await withTimeout(seconds: 3) { try await sendTask.value }
    #expect(payload["ok"] == .bool(true))
}
