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

/// Pede permissão para "Write", espera a resposta e ecoa o behavior recebido.
private let askingHarness = #"""
printf '{"type":"control_request","request_id":"ask-1","request":{"subtype":"can_use_tool","tool_name":"Write","display_name":"Write","input":{"file_path":"/tmp/x","content":"ok"},"tool_use_id":"toolu_1","permission_suggestions":[{"type":"setMode","mode":"acceptEdits","destination":"session"}]}}\n'
IFS= read -r resposta
behavior=$(printf '%s' "$resposta" | sed -n 's/.*"behavior":"\([^"]*\)".*/\1/p')
printf '{"type":"result","decidiu":"%s"}\n' "$behavior"
"""#

@Test func thePermissionRequestReachesTheConsumer() async throws {
    let channel = ControlChannel(transport: ProcessTransport())
    let stream = try await channel.start(launch(askingHarness))

    // `withTimeout` aqui não testa prazo nenhum — testa a rede. Uma regressão
    // em `respond` que nunca escreva (ou escreva errado) deixa o `read` do
    // harness falso bloqueado para sempre, e o `for try await` esperaria por
    // um fluxo que jamais termina. Sem a rede, isso trava a suíte inteira sem
    // nome de teste, sem asserção, sem saída nenhuma. Com ela, a regressão
    // vira `TimedOut` num teste nomeado, em segundos.
    let request = try await withTimeout(seconds: 3) { () async throws -> PermissionRequest? in
        var request: PermissionRequest?
        for try await output in stream {
            if case .permissionRequest(let r) = output {
                request = r
                try await channel.respond(to: r.id, with: .allow(updatedInput: nil))
            }
        }
        return request
    }
    let r = try #require(request)
    #expect(r.toolName == "Write")
    #expect(r.toolUseID == "toolu_1")
    #expect(r.suggestions.first?.mode == "acceptEdits")
}

@Test func allowIsWhatTheHarnessReceives() async throws {
    let channel = ControlChannel(transport: ProcessTransport())
    let stream = try await channel.start(launch(askingHarness))

    // Mesma rede que em `thePermissionRequestReachesTheConsumer`.
    let decided = try await withTimeout(seconds: 3) { () async throws -> String? in
        var decided: String?
        for try await output in stream {
            switch output {
            case .permissionRequest(let r):
                try await channel.respond(to: r.id, with: .allow(updatedInput: nil))
            case .conversation(let data):
                let v = try JSONDecoder().decode(JSONValue.self, from: data)
                if let d = v["decidiu"]?.stringValue { decided = d }
            case .unrecognizedControl(let u):
                Issue.record("quadro inesperado neste harness falso: \(u.raw)")
            }
        }
        return decided
    }
    #expect(decided == "allow")
}

@Test func denyIsWhatTheHarnessReceives() async throws {
    let channel = ControlChannel(transport: ProcessTransport())
    let stream = try await channel.start(launch(askingHarness))

    // Mesma rede que em `thePermissionRequestReachesTheConsumer`.
    let decided = try await withTimeout(seconds: 3) { () async throws -> String? in
        var decided: String?
        for try await output in stream {
            switch output {
            case .permissionRequest(let r):
                try await channel.respond(to: r.id, with: .deny(message: "não", interrupt: false))
            case .conversation(let data):
                let v = try JSONDecoder().decode(JSONValue.self, from: data)
                if let d = v["decidiu"]?.stringValue { decided = d }
            case .unrecognizedControl(let u):
                Issue.record("quadro inesperado neste harness falso: \(u.raw)")
            }
        }
        return decided
    }
    #expect(decided == "deny")
}

@Test func theUpdatedInputSurvivesTheRoundTrip() async throws {
    // Um inteiro no input não pode virar ponto flutuante na volta.
    let harness = #"""
    printf '{"type":"control_request","request_id":"ask-2","request":{"subtype":"can_use_tool","tool_name":"T","input":{"count":1}}}\n'
    IFS= read -r resposta
    printf '{"type":"result","eco":%s}\n' "$(printf '%s' "$resposta" | sed -n 's/.*"updatedInput":\({[^}]*}\).*/\1/p')"
    """#
    let channel = ControlChannel(transport: ProcessTransport())
    let stream = try await channel.start(launch(harness))

    // Mesma rede que em `thePermissionRequestReachesTheConsumer`.
    let echoed = try await withTimeout(seconds: 3) { () async throws -> JSONValue? in
        var echoed: JSONValue?
        for try await output in stream {
            switch output {
            case .permissionRequest(let r):
                try await channel.respond(to: r.id, with: .allow(updatedInput: r.input))
            case .conversation(let data):
                let v = try JSONDecoder().decode(JSONValue.self, from: data)
                if let e = v["eco"] { echoed = e }
            case .unrecognizedControl(let u):
                Issue.record("quadro inesperado neste harness falso: \(u.raw)")
            }
        }
        return echoed
    }
    #expect(echoed?["count"] == .int(1))
}

/// Controller ruling: uma resposta de permissão que chega depois que o harness
/// já saiu sozinho — sem `stop()` — é um caso comum, não uma emergência: o
/// usuário demora alguns segundos para clicar, e a sessão pode ter terminado
/// nesse meio-tempo. Antes desta correção, os dois ramos terminais da bomba
/// falhavam quem esperava resposta mas nunca marcavam `liveness = .closed`, e
/// um `respond` chegando depois passava pela guarda, batia num pipe sem
/// leitor, e o chamador via um erro do Foundation (EPIPE) em vez de
/// `ChannelError.channelClosed`.
@Test func respondAfterTheHarnessExitsOnItsOwnFailsWithChannelClosed() async throws {
    let channel = ControlChannel(transport: ProcessTransport())
    let stream = try await channel.start(launch("exit 0"))

    // Drena o fluxo até o fim sem chamar stop(): é a saída espontânea do
    // harness que este teste verifica, não o encerramento explícito — esse já
    // tem cobertura em `sendAfterStopFailsWithChannelClosed`.
    for try await _ in stream {}

    await #expect(throws: ControlChannel.ChannelError.channelClosed) {
        try await withTimeout(seconds: 3) {
            try await channel.respond(to: "id-tardio", with: .allow(updatedInput: nil))
        }
    }
}
