import Darwin
import Foundation
import HarnessCore

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
private final class StreamIO: @unchecked Sendable {
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
    func startReading(
        onLines: @escaping @Sendable ([Data]) -> Void,
        onFramingFailure: @escaping @Sendable (any Error) -> Void
    ) {
        outputHandle.readabilityHandler = { [self] handle in
            lock.lock()
            defer { lock.unlock() }
            guard !hasFinished, !hasFramingFailed else { return }
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
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
            guard !hasFinished else { return }
            errorBytes.append(handle.availableData)
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

    /// Lê o que já está no pipe sem nunca bloquear.
    ///
    /// `readDataToEndOfFile()` só volta quando *todo* escritor fecha o
    /// descritor, e um neto que herdou o pipe sobrevive ao harness — isso
    /// travaria o `terminationHandler` e o fluxo nunca terminaria. Tudo o que o
    /// filho escreveu antes de sair já está no pipe neste ponto, então uma
    /// varredura sem bloqueio pega a cauda inteira.
    private static func readPending(_ handle: FileHandle) -> Data {
        let descriptor = handle.fileDescriptor
        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            var poller = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&poller, 1, 0) > 0 else { return pending }
            let count = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { return pending }
            pending.append(contentsOf: buffer[0..<count])
        }
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

    public enum TransportError: Error {
        /// Não há processo vivo aceitando entrada — ou ele já saiu, ou o stdin
        /// já foi fechado por `endInput()`.
        case notRunning
    }

    private let framingLimit: Int
    private var process: Process?
    private var standardInput: FileHandle?
    private var io: StreamIO?

    public init(framingLimit: Int = 8 * 1024 * 1024) {
        self.framingLimit = framingLimit
    }

    /// Tudo que o harness escreveu em stderr até agora. Quando o fluxo termina,
    /// já inclui o que estava no pipe no instante da saída.
    public var standardError: String { io?.collectedStandardError ?? "" }

    /// Nil enquanto o processo ainda roda.
    public var terminationStatus: Int32? {
        guard let process, !process.isRunning else { return nil }
        return process.terminationStatus
    }

    public func start(_ launch: Launch) throws -> AsyncThrowingStream<Data, Error> {
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
        if await waitForExit(within: .seconds(5)) { return }

        kill(process.processIdentifier, SIGKILL)
        _ = await waitForExit(within: .seconds(3))
    }

    private func waitForExit(within duration: Duration) async -> Bool {
        let deadline = ContinuousClock.now + duration
        while ContinuousClock.now < deadline {
            if process?.isRunning != true { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return process?.isRunning != true
    }
}
