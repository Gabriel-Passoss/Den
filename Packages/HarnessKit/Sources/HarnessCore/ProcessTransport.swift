import Darwin
import Foundation

/// Segura o enquadrador, os handles e o stderr acumulado atrás de um lock.
///
/// `readabilityHandler` e `terminationHandler` rodam em filas diferentes, então
/// todo estado mutável compartilhado entre eles precisa de sincronização
/// explícita — sob concorrência estrita do Swift 6, capturar um `var` local
/// nesses closures nem compila.
///
/// As leituras dos descritores acontecem dentro do mesmo lock que o
/// enquadramento, e não fora dele: desarmar um `readabilityHandler` não espera
/// pelos callbacks já agendados, então o dreno final e um callback em voo
/// podem correr juntos. Lendo os dois sob o lock, os bytes chegam ao
/// enquadrador na mesma ordem em que saíram do pipe.
///
/// Interno, e não privado, de propósito: o teto da varredura final só é
/// mensurável chamando `readPending` direto. Pelo fluxo público ele fica
/// escondido atrás das centenas de KiB que o `readabilityHandler` drena
/// enquanto o filho ainda está vivo — ruído maior que o próprio teto.
final class StreamIO: @unchecked Sendable {
    private let lock = NSLock()
    private let outputHandle: FileHandle
    private let errorHandle: FileHandle
    private var framer: NDJSONFramer
    private var errorBytes = Data()
    private var hasFramingFailed = false
    private var hasFinished = false

    init(outputHandle: FileHandle, errorHandle: FileHandle, framingLimit: Int) {
        self.outputHandle = outputHandle
        self.errorHandle = errorHandle
        self.framer = NDJSONFramer(limit: framingLimit)
    }

    var collectedStandardError: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: errorBytes, as: UTF8.self)
    }

    /// Arma os dois leitores. `onFramingFailure` é chamado no máximo uma vez;
    /// depois dele o stdout para de ser enquadrado, mas o stderr continua sendo
    /// drenado — um pipe de stderr cheio trava o filho (spec §4.4).
    ///
    /// Todo caminho que volta *sem* consumir o descritor desarma o handler
    /// antes: `readabilityHandler` é disparado por nível (é uma dispatch source
    /// de leitura), então um bloco que devolve deixando bytes ou EOF legíveis é
    /// reagendado na hora, em laço fechado, queimando uma thread da fila
    /// compartilhada até alguém desarmar. Desarmar aqui é seguro porque o dreno
    /// final é o único outro leitor destes descritores, e ele começa
    /// justamente desarmando os dois.
    func startReading(
        onLines: @escaping @Sendable ([Data]) -> Void,
        onFramingFailure: @escaping @Sendable (any Error) -> Void
    ) {
        outputHandle.readabilityHandler = { [self] handle in
            lock.lock()
            defer { lock.unlock() }
            guard !hasFinished, !hasFramingFailed else {
                handle.readabilityHandler = nil
                return
            }
            // Chunk vazio num handle legível é EOF, e EOF num pipe é
            // definitivo: o nível fica alto para sempre.
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            do {
                onLines(try framer.push(chunk))
            } catch {
                hasFramingFailed = true
                onFramingFailure(error)
            }
        }

        errorHandle.readabilityHandler = { [self] handle in
            lock.lock()
            defer { lock.unlock() }
            guard !hasFinished else {
                handle.readabilityHandler = nil
                return
            }
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            errorBytes.append(chunk)
        }
    }

    /// Solta os handlers e devolve as linhas que ainda estavam no pipe de
    /// stdout. Idempotente: chamadas seguintes não devolvem nada.
    ///
    /// Desarmar os handlers acontece fora do lock de propósito — um callback em
    /// voo pode estar segurando ele neste instante.
    ///
    /// Propaga erro de enquadramento em vez de engolir: num processo curto que
    /// escreve e sai na mesma hora, o callback de leitura pode nunca chegar a
    /// rodar, e aí esta é a *única* passagem dos bytes pelo enquadrador.
    func finishReading() throws -> [Data] {
        outputHandle.readabilityHandler = nil
        errorHandle.readabilityHandler = nil

        lock.lock()
        defer { lock.unlock() }
        guard !hasFinished else { return [] }
        hasFinished = true

        errorBytes.append(Self.readPending(errorHandle))
        guard !hasFramingFailed else { return [] }
        do {
            return try framer.push(Self.readPending(outputHandle))
        } catch {
            hasFramingFailed = true
            throw error
        }
    }

    /// Tamanho de cada leitura da varredura — uma carga cheia de pipe.
    static let sweepReadSize = 64 * 1024

    /// Teto de bytes de uma varredura: duas cargas cheias de pipe.
    ///
    /// Um pipe no macOS guarda no máximo 65536 bytes (`BIG_PIPE_SIZE`, medido),
    /// e o filho já saiu quando a varredura começa — então a cauda legítima
    /// inteira cabe numa única leitura, e 128 KiB dão o dobro disso de folga sem
    /// nunca truncar saída de verdade. Manter o teto rente ao pipe também
    /// importa porque o dreno entrega tudo ao enquadrador de uma vez só: um teto
    /// generoso transformaria um neto tagarela num `framer.push` gigante.
    static let sweepByteLimit = 2 * sweepReadSize

    /// Prazo de uma varredura. O teto de bytes sozinho não fecha o caso do neto
    /// que goteja devagar: ele mantém o pipe quase sempre não-vazio sem nunca
    /// enchê-lo, e aí a varredura demoraria muito para bater no teto. 100 ms é
    /// ordens de grandeza mais do que uma drenagem honesta de ≤64 KiB precisa
    /// (microssegundos) e curto o bastante para não travar de forma perceptível
    /// nem o `terminationHandler` nem o `standardError`, que espera o mesmo lock.
    static let sweepBudget = Duration.milliseconds(100)

    /// Lê, sem nunca bloquear, o que já está no pipe — e para por aí.
    ///
    /// `readDataToEndOfFile()` só volta quando *todo* escritor fecha o
    /// descritor, e um neto que herdou o pipe sobrevive ao harness — isso
    /// travaria o `terminationHandler` e o fluxo nunca terminaria.
    ///
    /// A varredura é limitada de propósito. Tudo o que o filho escreveu antes de
    /// sair já está no pipe neste ponto; o que chegar depois veio de um neto que
    /// continua escrevendo, e persegui-lo é o mesmo travamento por outro
    /// caminho — ele reenche o pipe tão rápido quanto o dreno esvazia, `poll`
    /// nunca devolve 0, `continuation.finish()` nunca é alcançado, e isso tudo
    /// com o lock na mão e o buffer crescendo na velocidade do pipe. Perder o
    /// retardatário é melhor do que congelar a sessão.
    static func readPending(_ handle: FileHandle) -> Data {
        let descriptor = handle.fileDescriptor
        let deadline = ContinuousClock.now + sweepBudget
        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: sweepReadSize)
        while pending.count < sweepByteLimit, ContinuousClock.now < deadline {
            var poller = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&poller, 1, 0) > 0 else { break }
            let count = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { break }
            pending.append(contentsOf: buffer[0..<count])
        }
        return pending
    }
}

/// Dá spawn num harness de linha de comando e converte o stdout dele num
/// fluxo de linhas NDJSON.
///
/// stderr é drenado continuamente e sem exceção: um pipe de stderr cheio trava
/// o processo filho, e o sintoma é uma sessão que congela sem erro nenhum
/// (spec §4.4).
public actor ProcessTransport {
    public struct Launch: Sendable {
        public var executable: String
        public var arguments: [String]
        public var workingDirectory: URL
        public var environment: [String: String]

        public init(
            executable: String,
            arguments: [String],
            workingDirectory: URL,
            environment: [String: String] = ProcessInfo.processInfo.environment
        ) {
            self.executable = executable
            self.arguments = arguments
            self.workingDirectory = workingDirectory
            self.environment = environment
        }
    }

    public enum TransportError: Error, Equatable {
        /// Não há processo vivo aceitando entrada — ou ele já saiu, ou o stdin
        /// já foi fechado por `endInput()`.
        case notRunning
        /// `start(_:)` já subiu um processo neste transporte. Ver o contrato de
        /// uso único em `start(_:)`.
        case alreadyStarted
    }

    private let framingLimit: Int
    private let terminationGracePeriod: Duration
    private let killGracePeriod: Duration
    private var process: Process?
    private var standardInput: FileHandle?
    private var io: StreamIO?

    /// - Parameters:
    ///   - terminationGracePeriod: quanto `terminate()` espera pelo SIGTERM
    ///     antes de escalar para SIGKILL. Default 5 s (spec §5.5).
    ///   - killGracePeriod: quanto `terminate()` espera depois do SIGKILL.
    ///     Default 3 s (spec §5.5).
    ///
    /// As duas durações são injetáveis pela mesma razão que `framingLimit` é:
    /// com os defaults da spec, o ramo de escalada só seria observável num
    /// teste que gastasse 5 segundos de relógio. Com orçamentos curtos ele
    /// cabe em milissegundos, e o caminho que só roda em emergência deixa de
    /// ser código sem evidência nenhuma.
    public init(
        framingLimit: Int = 8 * 1024 * 1024,
        terminationGracePeriod: Duration = .seconds(5),
        killGracePeriod: Duration = .seconds(3)
    ) {
        self.framingLimit = framingLimit
        self.terminationGracePeriod = terminationGracePeriod
        self.killGracePeriod = killGracePeriod
    }

    /// Tudo que o harness escreveu em stderr até agora. Quando o fluxo termina,
    /// já inclui o que estava no pipe no instante da saída.
    public var standardError: String { io?.collectedStandardError ?? "" }

    /// O código de saída do processo, ou `nil` em duas situações distintas
    /// que este tipo não separa: o processo ainda está rodando, ou `start(_:)`
    /// nunca chegou a subir um (nunca foi chamado, ou falhou no `run()`). Quem
    /// precisar distinguir as duas tem que guardar por fora o fato de ter
    /// chamado `start(_:)` com sucesso.
    public var terminationStatus: Int32? {
        guard let process, !process.isRunning else { return nil }
        return process.terminationStatus
    }

    /// Sobe o harness e devolve o fluxo de linhas do stdout dele.
    ///
    /// **Um transporte é de uso único.** Um `start(_:)` bem-sucedido casa este
    /// transporte com um processo para sempre: `terminationStatus` continua
    /// respondendo pelo processo já colhido, e o fluxo, o stdin e os leitores
    /// pertencem àquela execução. Uma segunda chamada lança
    /// `TransportError.alreadyStarted` em vez de sobrescrever `process`,
    /// `standardInput` e `io` — sobrescrevê-los deixaria o primeiro filho vivo,
    /// com leitores armados e sem nenhuma referência capaz de alcançá-lo:
    /// exatamente o órfão que a spec §5.2 existe para impedir, e sem nenhum
    /// erro visível. Um ciclo `idle → hot` (spec §5.1) cria um transporte novo
    /// por ciclo; é barato, e é o que torna a reentrância irrepresentável em
    /// vez de meramente desaconselhada.
    ///
    /// A guarda é um `throw`, não uma `precondition`: `start(_:)` já lança, o
    /// chamador já trata erro, e derrubar o app inteiro por um reuso indevido
    /// seria pior do que o defeito que estamos prevenindo. Um erro é
    /// recuperável, testável e nomeia a causa.
    ///
    /// Um `start(_:)` que **falha** não queima o transporte: `process` só é
    /// preenchido depois de `run()` voltar, então uma tentativa de spawn
    /// malsucedida pode ser repetida.
    public func start(_ launch: Launch) throws -> AsyncThrowingStream<Data, Error> {
        guard self.process == nil else { throw TransportError.alreadyStarted }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch.executable)
        process.arguments = launch.arguments
        process.currentDirectoryURL = launch.workingDirectory
        process.environment = launch.environment

        let input = Pipe(), output = Pipe(), errorOutput = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errorOutput

        // Sem isso, escrever depois que o filho fechou o stdin dispara SIGPIPE,
        // cuja ação padrão mata o processo *pai* — o DevSpace inteiro. Com a
        // flag, o `write` devolve EPIPE e vira um erro que dá para tratar.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        let io = StreamIO(
            outputHandle: output.fileHandleForReading,
            errorHandle: errorOutput.fileHandleForReading,
            framingLimit: framingLimit
        )

        let stream = AsyncThrowingStream<Data, Error> { continuation in
            io.startReading(
                onLines: { lines in
                    for line in lines { continuation.yield(line) }
                },
                onFramingFailure: { error in
                    continuation.finish(throwing: error)
                    // Saída corrompida: ninguém mais vai ler o stdout dele, e
                    // sem isso o harness fica órfão travado na escrita.
                    Task { await self.terminate() }
                }
            )

            // Chamado uma única vez pelo Foundation. Recolhe a cauda que ainda
            // estava nos pipes entre o último callback de leitura e a saída.
            // `finish()` depois de um `finish(throwing:)` é no-op, então a
            // corrida com uma falha de enquadramento é inofensiva.
            process.terminationHandler = { _ in
                do {
                    for line in try io.finishReading() { continuation.yield(line) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        do {
            try process.run()
        } catch {
            // Sem filho, o `terminationHandler` nunca roda — e os leitores
            // armados segurariam o `StreamIO` vivo para sempre.
            _ = try? io.finishReading()
            throw error
        }

        // Só depois de subir de verdade: um `Process` que nunca rodou levanta
        // exceção quando alguém pergunta o `terminationStatus` dele.
        self.process = process
        self.standardInput = input.fileHandleForWriting
        self.io = io
        return stream
    }

    public func write(_ line: Data) throws {
        guard let standardInput, process?.isRunning == true else { throw TransportError.notRunning }
        try standardInput.write(contentsOf: line + Data("\n".utf8))
    }

    public func endInput() {
        try? standardInput?.close()
        standardInput = nil
    }

    /// SIGTERM, depois SIGKILL se necessário (spec §5.5).
    ///
    /// Aguarda por polling em vez de dormir o intervalo inteiro: um processo
    /// que obedece ao SIGTERM sai em milissegundos, e não faz sentido cobrar
    /// 5 segundos de todo encerramento bem comportado.
    public func terminate() async {
        guard let process, process.isRunning else { return }
        process.terminate()
        if await waitForExit(process, within: terminationGracePeriod) { return }

        kill(process.processIdentifier, SIGKILL)
        _ = await waitForExit(process, within: killGracePeriod)
    }

    /// Recebe o processo por parâmetro em vez de reler `self.process`.
    ///
    /// O laço atravessa pontos de suspensão, e ler o campo do actor depois de
    /// cada um deles significaria observar um processo possivelmente diferente
    /// do que `terminate()` acabou de sinalizar — devolvendo `true` para uma
    /// saída que não é a dele, ou mandando SIGKILL contra um pid já colhido.
    /// A guarda de uso único em `start(_:)` já impede que o campo mude, mas a
    /// correção certa é não depender disso: a decisão é sobre *este* processo,
    /// então é ele que precisa estar na mão.
    private func waitForExit(_ process: Process, within duration: Duration) async -> Bool {
        let deadline = ContinuousClock.now + duration
        while ContinuousClock.now < deadline {
            if !process.isRunning { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return !process.isRunning
    }
}
