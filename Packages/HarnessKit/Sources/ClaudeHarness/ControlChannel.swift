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
        /// `start(_:)` ainda não subiu um harness neste canal. Distinto de
        /// `.channelClosed`: aqui nunca houve harness nenhum.
        case notStarted
        /// O prazo de `requestTimeout` estourou sem resposta correlacionada.
        case timedOut
        /// O canal fechou — o harness saiu, o fluxo falhou, ou `stop()` foi
        /// chamado. Vale tanto para quem esperava resposta quando isso
        /// aconteceu quanto para quem chega depois. Distinto de `.notStarted`:
        /// aqui houve um harness, e ele não está mais lá.
        case channelClosed
        /// O harness respondeu com `subtype: "error"`.
        case requestFailed(String)
    }

    private let transport: ProcessTransport
    private let requestTimeout: Duration
    private var pending: [String: CheckedContinuation<JSONValue, Error>] = [:]
    private var nextRequestNumber = 0
    private var liveness: Liveness = .notStarted

    /// Em que ponto da vida o canal está.
    ///
    /// Três estados num campo só, e não dois booleanos: com `started`/`stopped`
    /// separados, "parado antes de ter começado" seria representável, e o
    /// chamador receberia o erro errado sobre o estado errado.
    private enum Liveness { case notStarted, running, closed }

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
        liveness = .running

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
    /// falha com `.timedOut`.
    ///
    /// Esse prazo tem **uma** exceção, e ela é real. `writeSync` faz um
    /// `write(2)` bloqueante com o job deste ator na mão. Se o harness parar de
    /// ler o próprio stdin e o pipe de 64 KiB encher, a escrita bloqueia
    /// segurando o ator, e todo job seguinte fica na fila atrás dela —
    /// inclusive `timeOut`, que é isolado aqui, e inclusive `stop()`. Nesse
    /// estado o prazo não chega a disparar e o canal não é alcançável.
    ///
    /// Ou seja: a espera é limitada *enquanto o filho continuar drenando o
    /// stdin*, e não incondicionalmente. A escrita síncrona é o preço de fechar
    /// a janela de correlação descrita acima; este é o outro lado da moeda, e
    /// está registrado aqui para que ninguém confie numa garantia que o código
    /// não dá.
    public func send(_ request: OutboundControlRequest) async throws -> JSONValue {
        switch liveness {
        case .notStarted: throw ChannelError.notStarted
        case .closed: throw ChannelError.channelClosed
        case .running: break
        }
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
        // Marcar antes de qualquer `await`: um `send` que chegue ao ator no
        // meio do encerramento tem que ver o canal fechado, não escrever num
        // stdin cujo dono está sendo morto — lá o erro seria um EPIPE de
        // Foundation vazando por uma API que promete `ChannelError`.
        liveness = .closed
        failAllPending(.channelClosed)
        await transport.terminate()
    }
}
