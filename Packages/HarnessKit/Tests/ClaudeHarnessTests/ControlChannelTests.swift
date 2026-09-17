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

/// Pede permissão para "Write" uma única vez e depois lê o stdin até o EOF —
/// fica vivo o bastante para o teste responder duas vezes sem que o canal
/// feche no meio.
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

/// Item 1 do review final, e o portão real desta correção.
///
/// O harness falso manda um `control_request` de subtipo que não conhecemos e
/// **bloqueia no `read`**, exatamente como o CLI real faz — ele mantém uma
/// tabela de pendentes e espera. Antes desta correção o quadro era classificado
/// certo e então descartado: o `read` nunca voltava, o fluxo nunca terminava, e
/// a sessão congelava sem uma linha de log. Era o sintoma que a spec §4.4 nomeia
/// e o inverso da §5.4, onde conteúdo desconhecido deve degradar.
///
/// Duas afirmações, e as duas importam: o harness **destrava** (a linha
/// `destravou` só é escrita depois de a resposta chegar) e o consumidor **vê** o
/// caso novo, com o `raw` preservado para o transcript.
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

    // Sem a rede, uma regressão aqui trava a suíte inteira em vez de falhar —
    // que é precisamente o defeito sob teste, um passo acima.
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
    // Spec §5.4: o quadro original fica inteiro para o transcript.
    #expect(u.raw["request"]?["subtype"] == .string("coisa_nova"))

    #expect(unblocked?["destravou"] == .string("error"))
    #expect(unblocked?["para"] == .string("u-1"))
    await channel.stop()
}

/// Item 4, do lado do canal: um `can_use_tool` sem `request_id` não pode virar
/// diálogo. Ele chega como registro, e sem resposta automática — porque não há
/// id para responder, e fingir que há seria escrever `request_id: ""` no fio.
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

/// Item 2 do review final. O canal entregava o pedido e o esquecia, então
/// `respond` escrevia resposta para qualquer string: id obsoleto, id inventado,
/// id já respondido. O vetor concreto é a resposta dupla — o usuário clica
/// Permitir e um "negar tudo" em lote dispara logo atrás — chegando à tabela de
/// pendentes do CLI, cujo comportamento nessa situação nunca observamos.
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
            // O harness falso continua vivo lendo o stdin de propósito — é isso
            // que mantém `liveness` em `.running` para a segunda resposta. Sair
            // do laço aqui, e não esperar o fluxo terminar.
            return
        }
        Issue.record("o harness falso nunca pediu permissão")
    }
    await channel.stop()
}

/// E um id que este canal nunca entregou também é recusado — com o canal vivo,
/// que é o que separa esta guarda da guarda de `liveness`.
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

/// Item 3 do review final — a janela que os comentários juravam não existir.
///
/// `liveness` só vira `.closed` quando a **bomba** observa o EOF do stdout. Este
/// harness falso abre a janela de propósito e a mantém aberta: fecha o próprio
/// stdin (`exec 0<&-`, o que faz o `write(2)` do lado de cá devolver EPIPE),
/// anuncia que fechou, e **continua vivo** com o stdout aberto — então a bomba
/// nunca vê EOF, `markClosed()` nunca roda, e a guarda de `liveness` passa
/// alegremente. É a mesma situação de um filho que morreu um milissegundo atrás,
/// só que sem depender de relógio nenhum: a linha `fechei` é a sincronização.
///
/// O teste existente (`respondAfterTheHarnessExitsOnItsOwnFailsWithChannelClosed`)
/// não alcança isto porque drena o fluxo até o fim antes de responder, o que
/// garante que `markClosed()` já correu.
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
                // A prova de que o stdin do filho já está fechado. Só agora a
                // escrita é garantidamente um EPIPE — e o filho segue vivo, logo
                // `liveness` segue `.running`.
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

/// O mesmo para `send(_:)`, que tem a mesma guarda e a mesma janela.
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
