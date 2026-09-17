import Foundation
import HarnessCore

/// O que sai de um `ControlChannel` para quem o consome.
public enum ChannelOutput: Sendable {
    /// Linha de conversa, crua. A Etapa 4 a mapeia; o canal não a interpreta.
    case conversation(Data)
    /// O harness pediu permissão. Responda com `respond(to:with:)`.
    case permissionRequest(PermissionRequest)
    /// Chegou um quadro de controle que não sabemos atender. O canal já
    /// resolveu o lado do protocolo (ver `UnrecognizedControl`); este caso
    /// existe para que o lado humano também seja resolvido.
    case unrecognizedControl(UnrecognizedControl)
}

/// Um quadro de controle que o canal não soube interpretar, mais o que ele
/// fez a respeito.
///
/// Este tipo existe porque a camada era honesta sobre tudo que reconhece e
/// silenciosa sobre a única coisa que não reconhece. O consumidor é uma UI
/// que precisa mostrar **alguma coisa** ao usuário quando uma ferramenta foi
/// recusada por não termos entendido o pedido — e "alguma coisa" não pode ser
/// inventada pela UI, senão ela e o harness contam histórias diferentes sobre
/// a mesma recusa.
public struct UnrecognizedControl: Equatable, Sendable {
    /// O `request_id` do quadro, quando havia um respondível. `nil` significa
    /// que não havia — e portanto que **não há como destravar o harness**.
    public let requestID: String?
    /// O quadro inteiro, como veio do fio. Spec §5.4: nada é perdido; o
    /// transcript guarda o original e um mapper corrigido o reinterpreta depois.
    public let raw: JSONValue
    /// A mensagem de erro que respondemos ao harness, ou `nil` se não
    /// respondemos.
    ///
    /// Carregar a mensagem, em vez de só registrá-la no log, é deliberado: é
    /// literalmente o que o harness recebeu, então é o texto que mantém a UI e
    /// a sessão contando a mesma história.
    public let automaticReply: String?

    /// `false` quer dizer que o harness **continua esperando** por este quadro
    /// — uma sessão travada, não uma sessão degradada. São dois estados de UI
    /// muito diferentes, e esta é a bandeira que os separa.
    public var wasAnswered: Bool { automaticReply != nil }

    public init(requestID: String?, raw: JSONValue, automaticReply: String?) {
        self.requestID = requestID
        self.raw = raw
        self.automaticReply = automaticReply
    }
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
        /// `respond(to:with:)` recebeu um id que este canal não entregou, ou
        /// que já foi respondido. Sem esta guarda, dois `control_response`
        /// para o mesmo `request_id` — o usuário clica Permitir e logo em
        /// seguida um "negar tudo" em lote dispara — chegariam à tabela de
        /// pendentes do CLI, cujo comportamento nessa situação nunca
        /// observamos.
        case unknownRequest(String)
    }

    private let transport: ProcessTransport
    private let requestTimeout: Duration
    private var pending: [String: CheckedContinuation<JSONValue, Error>] = [:]
    /// Os `request_id` de permissão que já entregamos ao consumidor e que
    /// ainda não foram respondidos.
    ///
    /// Sem este conjunto, `respond` escreve uma resposta para qualquer string:
    /// id obsoleto, id inventado, id já respondido. E a spec §5.6 ("permissão
    /// pendente no fechamento ... registrada como `.expired`") fica impossível
    /// de implementar de qualquer outra camada — este ator é o único
    /// componente que enxerga o conjunto em aberto.
    private var outstandingPermissions: Set<String> = []
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
                    await self?.markClosed()
                    continuation.finish()
                } catch {
                    await self?.markClosed()
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
            // Antes de entregar, e não depois: `consume` roda isolado neste
            // ator e retorna antes de a bomba fazer o `yield`, então não existe
            // instante em que o consumidor enxergue um pedido cujo id `respond`
            // ainda recusaria.
            outstandingPermissions.insert(request.id)
            return .permissionRequest(request)
        case .response(let id, let result):
            resolve(id, result)
            return nil
        case .unansweredControlRequest(let id, let raw):
            return .unrecognizedControl(refuse(id, raw))
        case .unknownControl(let raw):
            // Spec §5.4: desconhecido não é erro. Aqui não há id para
            // responder, então tudo que podemos fazer é não mentir sobre isso:
            // `automaticReply` nil diz ao consumidor que o harness pode estar
            // esperando por algo que nunca vai chegar.
            return .unrecognizedControl(
                UnrecognizedControl(requestID: nil, raw: raw, automaticReply: nil)
            )
        }
    }

    /// O texto da recusa automática. Uma constante, e não uma string montada
    /// no ponto de uso, porque ela sai por dois caminhos ao mesmo tempo — pelo
    /// fio, para o harness, e pelo `ChannelOutput`, para a UI — e os dois
    /// precisam dizer exatamente a mesma coisa.
    static let refusalMessage =
        "DevSpace não reconheceu este control_request e não consegue atendê-lo"

    /// Responde `subtype: "error"` a um request que não sabemos atender, e
    /// devolve o registro do que aconteceu.
    ///
    /// Isto é o oposto de descartar: o CLI manda um `control_request` e
    /// **espera**. Um subtipo futuro, ou um `can_use_tool` cujo `tool_name` foi
    /// renomeado depois de um `brew upgrade`, congelaria toda sessão que
    /// tocasse uma ferramenta com portão — o usuário veria um spinner e nada
    /// mais. Respondendo erro, a sessão degrada para "aquela ferramenta foi
    /// recusada" (spec §5.4) e o `raw` fica preservado para o transcript.
    ///
    /// A escrita é `writeSync` e acontece dentro da bomba. Vale aqui a mesma
    /// ressalva de `send(_:)`: é um `write(2)` bloqueante, e um harness que
    /// parasse de ler o próprio stdin com o pipe cheio travaria a bomba. A
    /// alternativa — despachar num `Task` — abriria a janela em que a recusa
    /// chega depois de o canal já ter sido fechado, e trocaria um risco raro
    /// por um comum.
    private func refuse(_ requestID: String, _ raw: JSONValue) -> UnrecognizedControl {
        do {
            try transport.writeSync(
                ControlErrorResponse(requestID: requestID, message: Self.refusalMessage).data()
            )
            return UnrecognizedControl(
                requestID: requestID, raw: raw, automaticReply: Self.refusalMessage
            )
        } catch {
            // Não conseguimos escrever — o harness já saiu, ou o stdin já foi
            // fechado. `automaticReply` nil é a diferença entre "recusamos" e
            // "nem isso deu".
            return UnrecognizedControl(requestID: requestID, raw: raw, automaticReply: nil)
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

    /// Controller ruling: os dois ramos terminais da bomba chamavam
    /// `failAllPending(.channelClosed)` sem nunca marcar `liveness = .closed`.
    /// Quem esperava resposta via o erro certo, mas um `send`/`respond` que
    /// chegasse *depois* — o harness saiu sozinho, sem `stop()` — via a
    /// guarda de `liveness` ainda em `.running`, a escrita batia num pipe sem
    /// leitor do outro lado, e o erro que vazava era do Foundation (EPIPE),
    /// não `ChannelError`. Isso é exatamente o defeito que `Liveness` foi
    /// criado para eliminar, entrando pela outra porta: uma sessão que
    /// termina sozinha — uma queda, ou um fim de sessão normal — é tão comum
    /// quanto um `stop()` explícito, e merece o mesmo vocabulário de erro.
    private func markClosed() {
        liveness = .closed
        failAllPending(.channelClosed)
        // Spec §5.6: uma permissão pendente morre com o processo. Quem quiser
        // registrá-la como `.expired` lê o conjunto antes de o canal fechar —
        // depois disso ela não é mais respondível, e mantê-la aqui só faria
        // `respond` escolher entre dois erros igualmente verdadeiros.
        outstandingPermissions.removeAll()
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
                // `ChannelError`, e não o erro cru: a guarda de `liveness`
                // acima não fecha a janela em que o filho já morreu e a bomba
                // ainda não viu o EOF. Nessa janela `writeSync` devolve um
                // `NSError`/EPIPE do Foundation, e ele chegaria a um chamador a
                // quem esta API prometeu `ChannelError.channelClosed`. Um pipe
                // que não aceita mais bytes é o canal fechado, não importa qual
                // dos dois lados percebeu primeiro.
                continuation.resume(throwing: ChannelError.channelClosed)
            }
        }
    }

    private func timeOut(_ id: String) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(throwing: ChannelError.timedOut)
    }

    /// Responde a um pedido de permissão.
    ///
    /// Não há resposta a esperar: a decisão é o fim da troca. Se o consumidor
    /// nunca responder, o harness fica bloqueado — é por isso que o pedido
    /// carrega o `id` e não um callback.
    ///
    /// Mesma guarda de três estados que `send(_:)`, e pela mesma razão: uma
    /// decisão do usuário chega em segundos, não instantaneamente, e a sessão
    /// pode muito bem ter terminado nesse meio-tempo — de propósito
    /// (`stop()`), ou sozinha (o harness saiu, `markClosed()` correu). Sem
    /// esta guarda, `respond` cairia direto em `transport.writeSync`, que
    /// bateria num pipe sem leitor do outro lado e devolveria um erro do
    /// Foundation em vez de `ChannelError.channelClosed`.
    public func respond(to requestID: String, with decision: PermissionDecision) throws {
        switch liveness {
        case .notStarted: throw ChannelError.notStarted
        case .closed: throw ChannelError.channelClosed
        case .running: break
        }
        // O id tem que ser um que *nós* entregamos e que ainda está em aberto.
        // A verificação vem depois da de `liveness` de propósito: quando o
        // canal fechou, "o canal fechou" é a explicação mais útil para o
        // chamador, e o conjunto já foi esvaziado de qualquer forma.
        guard outstandingPermissions.contains(requestID) else {
            throw ChannelError.unknownRequest(requestID)
        }
        let data = try decision.responseData(requestID: requestID)
        do {
            try transport.writeSync(data)
        } catch {
            // Mesma janela que `send(_:)` documenta, e pela mesma razão.
            throw ChannelError.channelClosed
        }
        // Só depois de a resposta ter de fato chegado ao fio. Se a escrita
        // falhou, o harness não foi respondido — e marcar o pedido como
        // respondido aqui apagaria justamente o que a spec §5.6 quer registrar.
        outstandingPermissions.remove(requestID)
    }

    /// Escreve um turno do usuário no stdin do harness.
    ///
    /// Saída de emergência — o pior caso da família. `transport.write(_:)` é
    /// membro do `ProcessTransport`, e a escrita que ele delega é bloqueante
    /// (ver o contrato de `ProcessTransport.writeSync(_:)`). Um harness que
    /// pare de ler o próprio stdin com o pipe de 64 KiB cheio trava esta
    /// chamada **segurando o job do `ProcessTransport`** — e `terminate()` é
    /// método desse mesmo ator. Ou seja: aqui não some só o prazo, como em
    /// `send(_:)`; some a última saída de emergência em que o comentário de
    /// `send(_:)` se apoia. E um turno de usuário é justamente o que mais
    /// facilmente passa de `PIPE_BUF`.
    ///
    /// A correção sistêmica (`O_NONBLOCK` + fila de escrita) é trabalho da
    /// Etapa 5. Isto está registrado aqui para que ninguém confie numa
    /// garantia que o código não dá.
    public func writeTurn(_ line: Data) async throws {
        try await transport.write(line)
    }

    /// Fecha o stdin do harness. Não há mais como escrever para ele depois
    /// disso — nem um turno, nem um request de controle, nem uma resposta de
    /// permissão — então o canal se considera fechado a partir daqui. Só
    /// `liveness`, e não `failAllPending`: um request ainda pendente pode
    /// muito bem receber sua resposta legítima depois disso — encerrar a
    /// nossa escrita não encerra a leitura do stdout dele, e é a bomba, não
    /// este método, quem sabe quando essa leitura de fato acaba.
    ///
    /// Saída de emergência: isto **não** serve para destravar uma escrita
    /// presa. `transport.endInput()` espera o mesmo mutex que a escrita segura
    /// (ver `ProcessTransport.endInput()`), então fechar o stdin de um harness
    /// que parou de lê-lo bloqueia aqui também.
    public func endInput() async {
        liveness = .closed
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
        outstandingPermissions.removeAll()
        await transport.terminate()
    }
}
