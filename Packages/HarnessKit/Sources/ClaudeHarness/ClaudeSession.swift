import Foundation
import HarnessCore

/// Uma sessão viva do Claude Code: sobe o processo, manda turnos, entrega o
/// que volta já traduzido.
///
/// É a costura das quatro camadas que já existiam separadas — `ProcessTransport`,
/// `ControlChannel`, `ClaudeEventMapper` e o vocabulário canônico — na ordem
/// que a spec §4.4 desenha.
///
/// **Esta é a fatia vertical, não a sessão completa da Etapa 5.** Falta o que
/// está escrito em `docs/superpowers/plans/2026-09-17-sessao-viva.md`:
/// gravação no store, acumulação de usage, interrupção com prazo, retomada
/// `idle → hot`, e permissão expirada no fechamento. O que existe aqui é o
/// suficiente para uma conversa aparecer numa janela.
public actor ClaudeSession {
    /// O que a sessão entrega a quem a consome.
    ///
    /// Um fluxo só, e não os dois de `MappedOutput`, porque o consumidor é uma
    /// UI: ela precisa dos deltas para pintar enquanto chega E das entradas
    /// consolidadas para trocar o rascunho pelo texto final. Isto **não**
    /// desfaz a separação da spec §4.4 — `SessionEvent` continua efêmero e
    /// `TranscriptEntry` continua durável; este envelope só os transporta
    /// juntos até o mesmo destinatário.
    public enum Update: Sendable {
        /// Efêmero: pinte agora, descarte depois.
        case event(SessionEvent)
        /// Durável: a forma consolidada, que vai para o transcript.
        case entry(TranscriptEntry)
        /// O harness quer permissão. Responda com `resolve(_:_:)`.
        case permission(PermissionRequest)
        /// Um quadro de controle que não soubemos atender (spec §5.4).
        case unrecognizedControl(UnrecognizedControl)
        /// A sessão acabou. `error` é `nil` quando o harness saiu sozinho.
        case ended(error: String?)
    }

    private let channel: ControlChannel
    private let mapper: ClaudeEventMapper
    private var pump: Task<Void, Never>?

    public init(channel: ControlChannel, mapper: ClaudeEventMapper = ClaudeEventMapper()) {
        self.channel = channel
        self.mapper = mapper
    }

    /// Sobe o harness e devolve o fluxo já traduzido.
    ///
    /// O fluxo é `AsyncStream` e não `AsyncThrowingStream` porque a falha vem
    /// como `.ended(error:)`: uma UI renderiza um caso a mais do vocabulário
    /// que ela já conhece com muito menos cerimônia do que um `for try await`
    /// com `catch` no meio de uma view.
    public func start(_ launch: ProcessTransport.Launch) async throws -> AsyncStream<Update> {
        let outputs = try await channel.start(launch)

        return AsyncStream<Update> { continuation in
            pump = Task { [mapper] in
                do {
                    for try await output in outputs {
                        switch output {
                        case .conversation(let line):
                            let mapped = mapper.map(line: line)
                            for event in mapped.events { continuation.yield(.event(event)) }
                            for entry in mapped.entries { continuation.yield(.entry(entry)) }
                        case .permissionRequest(let request):
                            // O quadro cru se perde aqui: `ChannelOutput` não o
                            // carrega. É a Task 1 do plano da sessão viva.
                            continuation.yield(.permission(request))
                        case .unrecognizedControl(let unrecognized):
                            continuation.yield(.unrecognizedControl(unrecognized))
                        }
                    }
                    continuation.yield(.ended(error: nil))
                } catch {
                    continuation.yield(.ended(error: String(describing: error)))
                }
                continuation.finish()
            }

            continuation.onTermination = { [weak self] _ in
                Task { await self?.stop() }
            }
        }
    }

    /// Manda um turno do usuário.
    ///
    /// A forma do fio está registrada em
    /// `docs/superpowers/notes-2026-09-17-protocolo-observado.md`: foi acertada
    /// de primeira contra o CLI real.
    public func send(_ text: String) async throws {
        let turn = JSONValue.object([
            "type": .string("user"),
            "message": .object([
                "role": .string("user"),
                "content": .string(text),
            ]),
        ])
        var line = try JSONEncoder().encode(turn)
        line.append(0x0A)
        try await channel.writeTurn(line)
    }

    /// Responde a um pedido de permissão.
    public func resolve(_ requestID: String, _ decision: PermissionDecision) async throws {
        try await channel.respond(to: requestID, with: decision)
    }

    /// Mata o harness e encerra a bomba.
    public func stop() async {
        pump?.cancel()
        pump = nil
        await channel.stop()
    }
}
