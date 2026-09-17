import Foundation
import HarnessCore

/// O que sai de um `ControlChannel` para quem o consome.
public enum ChannelOutput: Sendable {
    /// Linha de conversa, crua. A Etapa 4 a mapeia; o canal não a interpreta.
    case conversation(Data)
    /// O harness pediu permissão. Responda com `respond(to:with:)`.
    case permissionRequest(PermissionRequest)
}

/// Fala o protocolo de controle por cima de um `ProcessTransport`.
///
/// O stdout do harness carrega duas conversas entrelaçadas: mensagens da
/// sessão e quadros de controle. Este ator as separa, correlaciona as respostas
/// dos requests que enviamos, e entrega os pedidos de permissão ao consumidor.
public actor ControlChannel {
    public enum ChannelError: Error, Equatable {
        /// `start(_:)` ainda não subiu um harness neste canal.
        case notStarted
        /// O prazo de `requestTimeout` estourou sem resposta correlacionada.
        case timedOut
        /// O canal fechou (o harness saiu, o fluxo falhou, ou `stop()` foi
        /// chamado) enquanto este request esperava resposta. Distinto de
        /// `.notStarted`: aqui o pedido chegou a ser escrito num harness vivo.
        case channelClosed
        /// O harness respondeu com `subtype: "error"`.
        case requestFailed(String)
    }

    private let transport: ProcessTransport
    private let requestTimeout: Duration
    private var pending: [String: CheckedContinuation<JSONValue, Error>] = [:]
    private var nextRequestNumber = 0
    private var started = false

    public init(transport: ProcessTransport, requestTimeout: Duration = .seconds(30)) {
        self.transport = transport
        self.requestTimeout = requestTimeout
    }

    /// Sobe o harness e devolve o fluxo já demultiplexado.
    ///
    /// Quem consome o fluxo é dono do encerramento: abandonar a iteração
    /// cancela a bomba interna, mas **não** mata o filho. Chame `stop()`.
    public func start(
        _ launch: ProcessTransport.Launch
    ) async throws -> AsyncThrowingStream<ChannelOutput, Error> {
        let lines = try await transport.start(launch)
        started = true

        return AsyncThrowingStream<ChannelOutput, Error> { continuation in
            let pump = Task { [weak self] in
                do {
                    for try await line in lines {
                        guard let self else { break }
                        if let output = await self.consume(line) {
                            continuation.yield(output)
                        }
                    }
                    await self?.failAllPending(.channelClosed)
                    continuation.finish()
                } catch {
                    await self?.failAllPending(.channelClosed)
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in pump.cancel() }
        }
    }

    /// Classifica uma linha. Devolve o que o consumidor deve ver, ou `nil` se o
    /// quadro foi consumido internamente.
    private func consume(_ line: Data) -> ChannelOutput? {
        switch ControlFrame.classify(line) {
        case .conversation:
            return .conversation(line)
        case .permissionRequest(let request):
            return .permissionRequest(request)
        case .response(let id, let result):
            resolve(id, result)
            return nil
        case .unknownControl:
            // Spec §5.4: desconhecido não é erro. Não é conversa e não é nosso;
            // descartamos sem derrubar a sessão.
            return nil
        }
    }

    private func resolve(_ id: String, _ result: ControlResponseResult) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        switch result {
        case .success(let payload): continuation.resume(returning: payload)
        case .failure(let message): continuation.resume(throwing: ChannelError.requestFailed(message))
        }
    }

    /// Falha todo mundo que ainda espera resposta. Esvazia o dicionário
    /// *antes* de retomar as continuations: retomar é o que devolve o controle
    /// a quem chamou `send(_:)`, e ele pode chamar `send` de novo ali mesmo.
    /// Iterar sobre uma cópia e deixar `pending` limpo torna a reentrância
    /// inofensiva, e garante que nenhuma continuation seja retomada duas vezes.
    private func failAllPending(_ error: ChannelError) {
        let waiting = pending
        pending.removeAll()
        for (_, continuation) in waiting { continuation.resume(throwing: error) }
    }

    /// Envia um request de controle e espera a resposta correlacionada.
    ///
    /// A ordem aqui é o ponto inteiro do método. O corpo de
    /// `withCheckedThrowingContinuation` roda de forma síncrona e ainda dentro
    /// do ator, e `writeSync` é `nonisolated` — então entre registrar o
    /// pendente e escrever o pedido não existe ponto de suspensão nenhum.
    /// Trocar `writeSync` pelo `write` do ator reabriria a janela em que a
    /// resposta é classificada, não encontra dono, e o chamador espera para
    /// sempre. Ver `ProcessTransport.writeSync(_:)`.
    ///
    /// Cada continuation é retomada no máximo uma vez porque todo caminho que
    /// retoma (`resolve`, `timeOut`, `failAllPending`) é isolado neste ator e
    /// *remove* a entrada antes de retomar: quem chega primeiro leva, quem
    /// chega depois não acha nada.
    ///
    /// Se a task chamadora for cancelada enquanto espera, a continuation não é
    /// retomada na hora — ela sobrevive até o prazo de `requestTimeout` e
    /// falha com `.timedOut`. A espera é limitada, nunca infinita.
    public func send(_ request: OutboundControlRequest) async throws -> JSONValue {
        guard started else { throw ChannelError.notStarted }
        nextRequestNumber += 1
        let id = "devspace-\(nextRequestNumber)"
        let data = try request.requestData(requestID: id)

        // Herda o isolamento deste ator, então `timeOut` corre serializado com
        // `resolve` — é isso que impede o par "resposta chegou" / "prazo
        // estourou" de retomar a mesma continuation duas vezes.
        let timeout = Task { [requestTimeout] in
            try? await Task.sleep(for: requestTimeout)
            if !Task.isCancelled { timeOut(id) }
        }
        defer { timeout.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                try transport.writeSync(data)
            } catch {
                pending.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
    }

    private func timeOut(_ id: String) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(throwing: ChannelError.timedOut)
    }

    /// Escreve um turno do usuário no stdin do harness.
    public func writeTurn(_ line: Data) async throws {
        try await transport.write(line)
    }

    public func endInput() async {
        await transport.endInput()
    }

    /// Mata o harness e falha quem ainda espera resposta.
    ///
    /// É o encerramento explícito do canal: abandonar o fluxo sozinho cancela a
    /// bomba interna mas deixa o filho vivo com o stdout sem leitor.
    public func stop() async {
        failAllPending(.channelClosed)
        await transport.terminate()
    }
}
