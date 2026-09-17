# HarnessKit — Transporte e Gravador (Etapas 0–2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construir o núcleo headless que dá spawn no `claude`, enquadra o NDJSON que sai dele e grava sessões reais em arquivos de fixture.

**Architecture:** Um pacote SPM local (`Packages/HarnessKit`) sem dependências externas, desenvolvido e testado inteiramente pela linha de comando com `swift test` — o projeto Xcode não é tocado até a etapa 5. Três peças independentes (enquadramento, descoberta, transporte) e um executável de diagnóstico que as costura.

**Tech Stack:** Swift 6.4, SwiftPM, Swift Testing (`import Testing`), Foundation `Process`. Zero dependências de terceiros.

**Spec:** `docs/superpowers/specs/2026-09-16-devspace-fundacao-design.md`

## Global Constraints

- Swift tools 6.0; plataforma mínima do pacote `.macOS(.v15)`.
- **Zero dependências externas** no `Package.swift`. Não adicionar ArgumentParser, GRDB ou qualquer outra.
- Framework de teste: Swift Testing (`import Testing`, `@Test`, `#expect`), não XCTest.
- Teto de enquadramento NDJSON: **8 MiB por linha** (spec §4.4).
- Timeouts de encerramento: `SIGTERM` após **5 segundos**, `SIGKILL` após mais **3 segundos** (spec §5.5).
- Nunca resolver o symlink do `claude` para o caminho versionado do Homebrew — guardar o caminho lógico (spec §4.4).
- Nenhuma tarefa deste plano toca em `~/.claude/projects/*.jsonl`. Formato privado (spec §12).
- Testes que executam o `claude` real levam `.tags(.integration)` e não rodam por padrão.

---

## File Structure

| Arquivo | Responsabilidade |
|---|---|
| `Packages/HarnessKit/Package.swift` | Manifesto: alvos `HarnessCore`, `ClaudeHarness`, `harness-probe` e testes |
| `Sources/HarnessCore/NDJSONFramer.swift` | Bytes → linhas JSON completas; buffer parcial; teto de tamanho |
| `Sources/ClaudeHarness/CommandRunner.swift` | Protocolo de execução de comando + implementação real (injetável para teste) |
| `Sources/ClaudeHarness/ClaudeDiscovery.swift` | Localiza o binário via shell de login, lê a versão |
| `Sources/ClaudeHarness/ProcessTransport.swift` | Spawn, pipes, dreno de stderr, escrita em stdin, encerramento |
| `Sources/harness-probe/main.swift` | CLI de diagnóstico: `discover` e `record` |
| `Tests/HarnessCoreTests/NDJSONFramerTests.swift` | Enquadramento: fronteiras de chunk, linhas vazias, teto |
| `Tests/ClaudeHarnessTests/ClaudeDiscoveryTests.swift` | Descoberta com runner falso + um teste de integração |
| `Tests/ClaudeHarnessTests/ProcessTransportTests.swift` | Transporte contra `/bin/sh` fazendo papel de harness falso |

---

### Task 1: Pacote HarnessKit + enquadramento NDJSON

O scaffolding do pacote está dobrado aqui porque é o enquadrador que primeiro precisa dele.

**Files:**
- Create: `Packages/HarnessKit/Package.swift`
- Create: `Packages/HarnessKit/Sources/HarnessCore/NDJSONFramer.swift`
- Test: `Packages/HarnessKit/Tests/HarnessCoreTests/NDJSONFramerTests.swift`

**Interfaces:**
- Consumes: nada.
- Produces: `NDJSONFramer` com `init(limit: Int = 8 * 1024 * 1024)`, `mutating func push(_ chunk: Data) throws -> [Data]` e `enum NDJSONFramer.FramingError: Error, Equatable { case lineTooLong(limit: Int) }`. A Task 3 usa exatamente esta assinatura.

- [ ] **Step 1: Criar o manifesto do pacote**

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HarnessKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "HarnessCore", targets: ["HarnessCore"]),
        .library(name: "ClaudeHarness", targets: ["ClaudeHarness"]),
        .executable(name: "harness-probe", targets: ["harness-probe"]),
    ],
    targets: [
        .target(name: "HarnessCore"),
        .target(name: "ClaudeHarness", dependencies: ["HarnessCore"]),
        .executableTarget(name: "harness-probe", dependencies: ["ClaudeHarness"]),
        .testTarget(name: "HarnessCoreTests", dependencies: ["HarnessCore"]),
        .testTarget(name: "ClaudeHarnessTests", dependencies: ["ClaudeHarness", "HarnessCore"]),
    ]
)
```

- [ ] **Step 2: Escrever os testes que falham**

```swift
import Testing
import Foundation
@testable import HarnessCore

@Test func entregaUmaLinhaCompleta() throws {
    var framer = NDJSONFramer()
    let lines = try framer.push(Data(#"{"a":1}"# .utf8) + Data("\n".utf8))
    #expect(lines.count == 1)
    #expect(String(decoding: lines[0], as: UTF8.self) == #"{"a":1}"#)
}

@Test func seguraLinhaPartidaEntreChunks() throws {
    var framer = NDJSONFramer()
    #expect(try framer.push(Data(#"{"a":"# .utf8)).isEmpty)
    let lines = try framer.push(Data("1}\n".utf8))
    #expect(lines.map { String(decoding: $0, as: UTF8.self) } == [#"{"a":1}"#])
}

@Test func entregaVariasLinhasDeUmChunkSo() throws {
    var framer = NDJSONFramer()
    let lines = try framer.push(Data("{\"a\":1}\n{\"b\":2}\n".utf8))
    #expect(lines.count == 2)
}

@Test func ignoraLinhasVazias() throws {
    var framer = NDJSONFramer()
    let lines = try framer.push(Data("\n\n{\"a\":1}\n\n".utf8))
    #expect(lines.count == 1)
}

@Test func removeCarriageReturnFinal() throws {
    var framer = NDJSONFramer()
    let lines = try framer.push(Data("{\"a\":1}\r\n".utf8))
    #expect(String(decoding: lines[0], as: UTF8.self) == #"{"a":1}"#)
}

@Test func estouraQuandoALinhaPassaDoTeto() {
    var framer = NDJSONFramer(limit: 16)
    #expect(throws: NDJSONFramer.FramingError.lineTooLong(limit: 16)) {
        _ = try framer.push(Data(String(repeating: "x", count: 32).utf8))
    }
}

@Test func naoEstouraQuandoOTotalPassaMasCadaLinhaCabe() throws {
    var framer = NDJSONFramer(limit: 16)
    let lines = try framer.push(Data("{\"a\":1}\n{\"b\":2}\n{\"c\":3}\n".utf8))
    #expect(lines.count == 3)
}
```

- [ ] **Step 3: Rodar os testes e confirmar que falham**

Run: `cd Packages/HarnessKit && swift test`
Expected: FAIL — `cannot find 'NDJSONFramer' in scope`.

- [ ] **Step 4: Implementar o enquadrador**

```swift
import Foundation

/// Converte um fluxo de bytes em linhas NDJSON completas.
///
/// Mantém em buffer a linha parcial entre chamadas, porque um chunk lido de um
/// pipe quase nunca coincide com a fronteira de uma linha.
public struct NDJSONFramer: Sendable {
    public enum FramingError: Error, Equatable {
        /// A linha parcial passou do teto sem nenhuma quebra de linha à vista.
        /// Sinaliza saída corrompida ou não-NDJSON — não vale continuar lendo.
        case lineTooLong(limit: Int)
    }

    private static let newline: UInt8 = 0x0A
    private static let carriageReturn: UInt8 = 0x0D

    private var buffer = Data()
    private let limit: Int

    public init(limit: Int = 8 * 1024 * 1024) {
        self.limit = limit
    }

    /// Consome um chunk e devolve as linhas que ficaram completas com ele.
    /// Linhas vazias são descartadas.
    public mutating func push(_ chunk: Data) throws -> [Data] {
        buffer.append(chunk)

        var lines: [Data] = []
        while let index = buffer.firstIndex(of: Self.newline) {
            var line = Data(buffer[buffer.startIndex..<index])
            buffer = Data(buffer[buffer.index(after: index)...])
            if line.last == Self.carriageReturn { line.removeLast() }
            if !line.isEmpty { lines.append(line) }
        }

        if buffer.count > limit {
            throw FramingError.lineTooLong(limit: limit)
        }
        return lines
    }
}
```

- [ ] **Step 5: Rodar os testes e confirmar que passam**

Run: `cd Packages/HarnessKit && swift test`
Expected: PASS, 7 testes.

- [ ] **Step 6: Commit**

```bash
git add Packages/HarnessKit
git commit -m "feat(harnesskit): pacote SPM e enquadramento NDJSON"
```

---

### Task 2: Descoberta do binário `claude`

**Files:**
- Create: `Packages/HarnessKit/Sources/ClaudeHarness/CommandRunner.swift`
- Create: `Packages/HarnessKit/Sources/ClaudeHarness/ClaudeDiscovery.swift`
- Test: `Packages/HarnessKit/Tests/ClaudeHarnessTests/ClaudeDiscoveryTests.swift`

**Interfaces:**
- Consumes: nada da Task 1.
- Produces: `struct HarnessInstallation: Equatable, Sendable { let executable: String; let version: String }`; `protocol CommandRunner: Sendable { func run(_ executable: String, _ arguments: [String]) async throws -> String }`; `struct SystemCommandRunner: CommandRunner`; `struct ClaudeDiscovery { init(runner: CommandRunner, shell: String, fallbackPaths: [String]); func discover() async throws -> HarnessInstallation }`; `enum ClaudeDiscovery.DiscoveryError: Error, Equatable { case notFound, unreadableVersion(String) }`. A Task 4 usa `discover()` e lê `.executable`.

- [ ] **Step 1: Escrever os testes que falham**

```swift
import Testing
import Foundation
@testable import ClaudeHarness

/// Runner falso: mapeia comando+args para uma saída fixa, ou lança se não mapeado.
struct FakeCommandRunner: CommandRunner {
    var responses: [String: String] = [:]
    func run(_ executable: String, _ arguments: [String]) async throws -> String {
        let key = ([executable] + arguments).joined(separator: " ")
        guard let out = responses[key] else {
            throw NSError(domain: "fake", code: 127)
        }
        return out
    }
}

@Test func achaOBinarioPeloShellDeLogin() async throws {
    let runner = FakeCommandRunner(responses: [
        "/bin/zsh -l -c command -v claude": "/opt/homebrew/bin/claude\n",
        "/opt/homebrew/bin/claude --version": "2.1.236 (Claude Code)\n",
    ])
    let install = try await ClaudeDiscovery(runner: runner, shell: "/bin/zsh", fallbackPaths: []).discover()
    #expect(install.executable == "/opt/homebrew/bin/claude")
    #expect(install.version == "2.1.236")
}

@Test func caiNoFallbackQuandoOShellNaoAcha() async throws {
    let runner = FakeCommandRunner(responses: [
        "/usr/local/bin/claude --version": "2.0.9 (Claude Code)\n",
    ])
    let install = try await ClaudeDiscovery(
        runner: runner, shell: "/bin/zsh", fallbackPaths: ["/usr/local/bin/claude"]
    ).discover()
    #expect(install.executable == "/usr/local/bin/claude")
    #expect(install.version == "2.0.9")
}

@Test func falhaComNotFoundQuandoNadaResponde() async {
    let runner = FakeCommandRunner()
    await #expect(throws: ClaudeDiscovery.DiscoveryError.notFound) {
        _ = try await ClaudeDiscovery(runner: runner, shell: "/bin/zsh", fallbackPaths: []).discover()
    }
}

@Test func falhaQuandoAVersaoNaoEhLegivel() async {
    let runner = FakeCommandRunner(responses: [
        "/bin/zsh -l -c command -v claude": "/opt/homebrew/bin/claude\n",
        "/opt/homebrew/bin/claude --version": "não sou uma versão\n",
    ])
    await #expect(throws: ClaudeDiscovery.DiscoveryError.unreadableVersion("não sou uma versão")) {
        _ = try await ClaudeDiscovery(runner: runner, shell: "/bin/zsh", fallbackPaths: []).discover()
    }
}

@Test func naoResolveOSymlinkParaOCaminhoVersionado() async throws {
    // O caminho lógico precisa sobreviver a um `brew upgrade` (spec §4.4).
    let runner = FakeCommandRunner(responses: [
        "/bin/zsh -l -c command -v claude": "/opt/homebrew/bin/claude\n",
        "/opt/homebrew/bin/claude --version": "2.1.236 (Claude Code)\n",
    ])
    let install = try await ClaudeDiscovery(runner: runner, shell: "/bin/zsh", fallbackPaths: []).discover()
    #expect(!install.executable.contains("Caskroom"))
}

@Test(.tags(.integration)) func achaOClaudeDeVerdade() async throws {
    let install = try await ClaudeDiscovery().discover()
    #expect(install.executable.hasSuffix("claude"))
    #expect(!install.version.isEmpty)
}
```

Adicionar ao mesmo arquivo, no topo, a definição da tag:

```swift
extension Tag {
    @Tag static var integration: Self
}
```

- [ ] **Step 2: Rodar e confirmar que falham**

Run: `cd Packages/HarnessKit && swift test --filter ClaudeDiscoveryTests`
Expected: FAIL — `cannot find 'ClaudeDiscovery' in scope`.

- [ ] **Step 3: Implementar o CommandRunner**

```swift
import Foundation

/// Executa um comando e devolve o stdout. Injetável para que a descoberta
/// possa ser testada sem depender do que está instalado na máquina.
public protocol CommandRunner: Sendable {
    func run(_ executable: String, _ arguments: [String]) async throws -> String
}

public struct SystemCommandRunner: CommandRunner {
    public init() {}

    public func run(_ executable: String, _ arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw CocoaError(.executableLoad)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
```

- [ ] **Step 4: Implementar a descoberta**

```swift
import Foundation

public struct HarnessInstallation: Equatable, Sendable {
    /// Caminho lógico, nunca o alvo resolvido do symlink: o Homebrew aponta
    /// para um diretório versionado que muda a cada atualização (spec §4.4).
    public let executable: String
    public let version: String

    public init(executable: String, version: String) {
        self.executable = executable
        self.version = version
    }
}

public struct ClaudeDiscovery: Sendable {
    public enum DiscoveryError: Error, Equatable {
        case notFound
        case unreadableVersion(String)
    }

    public static let defaultFallbackPaths = [
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        NSHomeDirectory() + "/.local/bin/claude",
        NSHomeDirectory() + "/.claude/local/claude",
    ]

    private let runner: CommandRunner
    private let shell: String
    private let fallbackPaths: [String]

    public init(
        runner: CommandRunner = SystemCommandRunner(),
        shell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
        fallbackPaths: [String] = ClaudeDiscovery.defaultFallbackPaths
    ) {
        self.runner = runner
        self.shell = shell
        self.fallbackPaths = fallbackPaths
    }

    public func discover() async throws -> HarnessInstallation {
        for candidate in try await candidates() {
            guard let version = try? await readVersion(of: candidate) else { continue }
            return HarnessInstallation(executable: candidate, version: version)
        }
        throw DiscoveryError.notFound
    }

    /// Um app aberto pelo Finder não herda o PATH do shell, então perguntamos
    /// ao shell de login antes de tentar os caminhos conhecidos (spec §4.4).
    private func candidates() async throws -> [String] {
        var found: [String] = []
        if let output = try? await runner.run(shell, ["-l", "-c", "command -v claude"]) {
            let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty { found.append(path) }
        }
        found.append(contentsOf: fallbackPaths)
        return found
    }

    private func readVersion(of executable: String) async throws -> String {
        let raw = try await runner.run(executable, ["--version"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Formato observado: "2.1.236 (Claude Code)"
        guard let match = raw.firstMatch(of: /^(\d+\.\d+\.\d+)/) else {
            throw DiscoveryError.unreadableVersion(raw)
        }
        return String(match.1)
    }
}
```

- [ ] **Step 5: Rodar e confirmar que passam**

Run: `cd Packages/HarnessKit && swift test --filter ClaudeDiscoveryTests`
Expected: PASS. O teste de integração também deve passar nesta máquina (`claude` 2.1.236 instalado).

- [ ] **Step 6: Commit**

```bash
git add Packages/HarnessKit
git commit -m "feat(harnesskit): descoberta do binário claude via shell de login"
```

---

### Task 3: Transporte de processo

**Files:**
- Create: `Packages/HarnessKit/Sources/ClaudeHarness/ProcessTransport.swift`
- Test: `Packages/HarnessKit/Tests/ClaudeHarnessTests/ProcessTransportTests.swift`

**Interfaces:**
- Consumes: `NDJSONFramer` da Task 1 (`push(_:) throws -> [Data]`).
- Produces: `actor ProcessTransport` com `struct ProcessTransport.Launch { var executable: String; var arguments: [String]; var workingDirectory: URL; var environment: [String: String] }`, `func start(_ launch: Launch) throws -> AsyncThrowingStream<Data, Error>`, `func write(_ line: Data) throws`, `func endInput()`, `func terminate() async`, `var standardError: String`, `var terminationStatus: Int32?`. Por serem membros de actor, todos são chamados com `await` de fora. A Task 4 usa `start`, `write`, `endInput` e `terminate`.

- [ ] **Step 1: Escrever os testes que falham**

O harness falso é `/bin/sh` rodando um script inline — nenhum arquivo de recurso necessário.

```swift
import Testing
import Foundation
import HarnessCore
@testable import ClaudeHarness

private func shellLaunch(_ script: String) -> ProcessTransport.Launch {
    ProcessTransport.Launch(
        executable: "/bin/sh",
        arguments: ["-c", script],
        workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
        environment: ProcessInfo.processInfo.environment
    )
}

@Test func leAsLinhasQueOProcessoEmite() async throws {
    let transport = ProcessTransport()
    let stream = try await transport.start(shellLaunch(#"printf '{"a":1}\n{"b":2}\n'"#))

    var received: [String] = []
    for try await line in stream {
        received.append(String(decoding: line, as: UTF8.self))
    }
    #expect(received == [#"{"a":1}"#, #"{"b":2}"#])
}

@Test func capturaOStandardError() async throws {
    let transport = ProcessTransport()
    let stream = try await transport.start(shellLaunch(#"echo aviso >&2; printf '{"a":1}\n'"#))
    for try await _ in stream {}
    let stderr = await transport.standardError
    #expect(stderr.contains("aviso"))
}

@Test func escreveNoStdinEOProcessoResponde() async throws {
    let transport = ProcessTransport()
    // Ecoa cada linha recebida de volta, envelopada.
    let stream = try await transport.start(shellLaunch(#"while read -r l; do printf '{"echo":%s}\n' "$l"; done"#))

    try await transport.write(Data(#"{"a":1}"# .utf8))
    try await transport.write(Data(#"{"b":2}"# .utf8))
    await transport.endInput()

    var received: [String] = []
    for try await line in stream {
        received.append(String(decoding: line, as: UTF8.self))
    }
    #expect(received == [#"{"echo":{"a":1}}"#, #"{"echo":{"b":2}}"#])
}

@Test func registraOCodigoDeSaida() async throws {
    let transport = ProcessTransport()
    let stream = try await transport.start(shellLaunch("exit 3"))
    for try await _ in stream {}
    let status = await transport.terminationStatus
    #expect(status == 3)
}

@Test func terminateDerrubaUmProcessoQueNaoTermina() async throws {
    let transport = ProcessTransport()
    let stream = try await transport.start(shellLaunch("sleep 60"))
    await transport.terminate()
    for try await _ in stream {}
    let status = await transport.terminationStatus
    #expect(status != nil)
}

@Test func propagaErroDeEnquadramento() async throws {
    let transport = ProcessTransport(framingLimit: 16)
    let stream = try await transport.start(shellLaunch(#"printf 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'"#))
    await #expect(throws: NDJSONFramer.FramingError.self) {
        for try await _ in stream {}
    }
}
```

- [ ] **Step 2: Rodar e confirmar que falham**

Run: `cd Packages/HarnessKit && swift test --filter ProcessTransportTests`
Expected: FAIL — `cannot find 'ProcessTransport' in scope`.

- [ ] **Step 3: Implementar o transporte**

```swift
import Foundation
import HarnessCore

/// Dá spawn num harness de linha de comando e converte o stdout dele num
/// fluxo de linhas NDJSON.
///
/// stderr é drenado continuamente e sem exceção: um pipe de stderr cheio
/// trava o processo filho, e o sintoma é uma sessão que congela sem erro
/// nenhum (spec §4.4).
/// Segura o enquadrador e os handles atrás de um lock.
///
/// Os handlers de `readabilityHandler` e `terminationHandler` rodam em filas
/// diferentes, então o estado mutável compartilhado entre eles precisa de
/// sincronização explícita — sob concorrência estrita do Swift 6, capturar um
/// `var` local nesses closures nem compila.
private final class StreamIO: @unchecked Sendable {
    private let lock = NSLock()
    private var framer: NDJSONFramer
    private let stdout: FileHandle
    private let stderr: FileHandle

    init(stdout: FileHandle, stderr: FileHandle, limit: Int) {
        self.stdout = stdout
        self.stderr = stderr
        self.framer = NDJSONFramer(limit: limit)
    }

    func frame(_ chunk: Data) throws -> [Data] {
        lock.lock(); defer { lock.unlock() }
        return try framer.push(chunk)
    }

    func onStandardOutput(_ handler: @escaping @Sendable (Data) -> Void) {
        stdout.readabilityHandler = { handler($0.availableData) }
    }

    func onStandardError(_ handler: @escaping @Sendable (Data) -> Void) {
        stderr.readabilityHandler = { handler($0.availableData) }
    }

    /// Solta os handlers e devolve o que sobrou no pipe de stdout.
    func detachAndDrain() -> Data {
        stdout.readabilityHandler = nil
        stderr.readabilityHandler = nil
        return stdout.readDataToEndOfFile()
    }
}

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
        case notRunning
    }

    private let framingLimit: Int
    private var process: Process?
    private var stdinPipe: Pipe?
    private var collectedStandardError = ""

    public init(framingLimit: Int = 8 * 1024 * 1024) {
        self.framingLimit = framingLimit
    }

    public var standardError: String { collectedStandardError }

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

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        self.process = process
        self.stdinPipe = stdin

        let io = StreamIO(
            stdout: stdout.fileHandleForReading,
            stderr: stderr.fileHandleForReading,
            limit: framingLimit
        )

        let stream = AsyncThrowingStream<Data, Error> { continuation in
            io.onStandardError { chunk in
                guard !chunk.isEmpty else { return }
                let text = String(decoding: chunk, as: UTF8.self)
                Task { await self.appendStandardError(text) }
            }

            io.onStandardOutput { chunk in
                guard !chunk.isEmpty else { return }
                do {
                    for line in try io.frame(chunk) { continuation.yield(line) }
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            process.terminationHandler = { _ in
                // Drena o que sobrou no pipe depois da saída do processo.
                let rest = io.detachAndDrain()
                if !rest.isEmpty, let lines = try? io.frame(rest) {
                    for line in lines { continuation.yield(line) }
                }
                continuation.finish()
            }
        }

        try process.run()
        return stream
    }

    public func write(_ line: Data) throws {
        guard let stdinPipe, process?.isRunning == true else { throw TransportError.notRunning }
        stdinPipe.fileHandleForWriting.write(line + Data("\n".utf8))
    }

    public func endInput() {
        try? stdinPipe?.fileHandleForWriting.close()
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

    private func appendStandardError(_ text: String) {
        collectedStandardError += text
    }
}
```

- [ ] **Step 4: Rodar e confirmar que passam**

Run: `cd Packages/HarnessKit && swift test --filter ProcessTransportTests`
Expected: PASS, 6 testes.

`terminateDerrubaUmProcessoQueNaoTermina` deve passar em bem menos de um
segundo: `/bin/sh` obedece ao `SIGTERM` e o polling percebe isso na hora. Se
demorar 5s, o `SIGTERM` não está chegando — investigar antes de seguir.

- [ ] **Step 5: Commit**

```bash
git add Packages/HarnessKit
git commit -m "feat(harnesskit): transporte de processo com enquadramento NDJSON e dreno de stderr"
```

---

### Task 4: `harness-probe` — descoberta e gravação

Esta é a tarefa que entrega a Etapa 2 da spec: ver o JSON real do Claude Code e produzir o primeiro fixture.

**Files:**
- Create: `Packages/HarnessKit/Sources/harness-probe/main.swift`

**Interfaces:**
- Consumes: `ClaudeDiscovery.discover()` (Task 2); `ProcessTransport.start/write/endInput/terminate` (Task 3).
- Produces: um executável. Nenhuma API consumida por tarefas posteriores.

- [ ] **Step 1: Escrever o executável**

Sem ArgumentParser — parsing manual, porque a restrição global é zero dependências.

```swift
import Foundation
import ClaudeHarness

func usage() -> Never {
    FileHandle.standardError.write(Data("""
    uso:
      harness-probe discover
      harness-probe record --prompt <texto> [--cwd <dir>] [--out <arquivo.ndjson>]

    """.utf8))
    exit(64)
}

func value(_ flag: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: flag), args.index(after: i) < args.endIndex else { return nil }
    return args[args.index(after: i)]
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }

switch command {
case "discover":
    let install = try await ClaudeDiscovery().discover()
    print("executável: \(install.executable)")
    print("versão:     \(install.version)")

case "record":
    guard let prompt = value("--prompt", in: args) else { usage() }
    let cwd = URL(fileURLWithPath: value("--cwd", in: args) ?? FileManager.default.currentDirectoryPath)
    let sessionID = UUID()

    let install = try await ClaudeDiscovery().discover()
    FileHandle.standardError.write(Data("→ \(install.executable) \(install.version), sessão \(sessionID)\n".utf8))

    let transport = ProcessTransport()
    let stream = try await transport.start(ProcessTransport.Launch(
        executable: install.executable,
        arguments: [
            "-p",
            "--output-format", "stream-json",
            "--input-format", "stream-json",
            "--include-partial-messages",
            "--verbose",
            "--session-id", sessionID.uuidString.lowercased(),
        ],
        workingDirectory: cwd
    ))

    // O turno do usuário, no formato de entrada do stream-json.
    //
    // ATENÇÃO: este shape é a hipótese de partida, não fato verificado. Se o
    // CLI reclamar no stderr, o formato correto aparece ali — corrigir aqui e
    // anotar no commit. Descobrir isso é justamente o objetivo desta etapa.
    let turn: [String: Any] = [
        "type": "user",
        "message": ["role": "user", "content": prompt],
    ]
    try await transport.write(try JSONSerialization.data(withJSONObject: turn))
    await transport.endInput()

    var recorded = Data()
    var count = 0
    for try await line in stream {
        recorded.append(line)
        recorded.append(0x0A)
        count += 1
        // Toda linha vai para stdout como veio, sem interpretação: o objetivo
        // desta etapa é justamente descobrir o formato.
        FileHandle.standardOutput.write(line + Data("\n".utf8))
    }

    if let out = value("--out", in: args) {
        try recorded.write(to: URL(fileURLWithPath: out))
        FileHandle.standardError.write(Data("← \(count) linhas gravadas em \(out)\n".utf8))
    }

    let stderr = await transport.standardError
    if !stderr.isEmpty {
        FileHandle.standardError.write(Data("stderr do harness:\n\(stderr)\n".utf8))
    }
    if let status = await transport.terminationStatus, status != 0 {
        FileHandle.standardError.write(Data("saída com código \(status)\n".utf8))
        exit(status)
    }

default:
    usage()
}
```

- [ ] **Step 2: Compilar**

Run: `cd Packages/HarnessKit && swift build`
Expected: compila sem erros.

- [ ] **Step 3: Verificar a descoberta**

Run: `cd Packages/HarnessKit && swift run harness-probe discover`
Expected: imprime caminho e versão, por exemplo `/opt/homebrew/bin/claude` e `2.1.236`.

- [ ] **Step 4: Gravar a primeira sessão real**

Usar um diretório descartável para não deixar o `claude` mexer no repositório.

```bash
mkdir -p /tmp/probe-scratch
cd Packages/HarnessKit
mkdir -p Tests/ClaudeHarnessTests/Fixtures
swift run harness-probe record \
  --prompt "Diga apenas OK e nada mais." \
  --cwd /tmp/probe-scratch \
  --out Tests/ClaudeHarnessTests/Fixtures/hello.ndjson
```

Expected: linhas JSON aparecem no terminal e o arquivo é criado. **Este é o entregável da Etapa 2.**

- [ ] **Step 5: Gravar uma sessão com uso de ferramenta e pedido de permissão**

É a gravação que o plano seguinte (protocolo de controle e mapper) vai consumir.

```bash
cd Packages/HarnessKit
swift run harness-probe record \
  --prompt "Liste os arquivos do diretório atual usando o bash." \
  --cwd /tmp/probe-scratch \
  --out Tests/ClaudeHarnessTests/Fixtures/tool-use.ndjson
```

Expected: o fluxo contém uso de ferramenta. Se a sessão travar esperando aprovação, é exatamente o request de controle que o próximo plano vai tratar — interromper com Ctrl-C e anotar o que apareceu por último.

- [ ] **Step 6: Inspecionar e registrar os tipos observados**

```bash
cd Packages/HarnessKit
cat Tests/ClaudeHarnessTests/Fixtures/*.ndjson \
  | python3 -c "import sys,json;from collections import Counter;c=Counter(json.loads(l).get('type','?') for l in sys.stdin if l.strip());print(c)"
```

Anotar a saída no corpo do commit: é o insumo direto do próximo plano.

- [ ] **Step 7: Commit**

```bash
git add Packages/HarnessKit
git commit -m "feat(harnesskit): harness-probe com discover e record

Primeiros fixtures gravados do Claude Code 2.1.236.
Tipos observados: <colar a saída do passo 6>"
```

---

### Task 5: Preparar o alvo do app

O app não é tocado nas Tasks 1–4, mas o App Sandbox é um bloqueio conhecido e documentado (spec §3.1). Desligar agora custa uma linha e evita descobrir na Etapa 5.

**Files:**
- Modify: `DevSpace.xcodeproj/project.pbxproj` (configurações `ENABLE_APP_SANDBOX`)

**Interfaces:**
- Consumes: nada.
- Produces: nada consumido por código.

- [ ] **Step 1: Conferir o estado atual**

Run: `grep -n 'ENABLE_APP_SANDBOX' DevSpace.xcodeproj/project.pbxproj`
Expected: uma ou mais linhas com `ENABLE_APP_SANDBOX = YES;` (Debug e Release).

- [ ] **Step 2: Desligar o sandbox**

```bash
sed -i '' 's/ENABLE_APP_SANDBOX = YES;/ENABLE_APP_SANDBOX = NO;/g' DevSpace.xcodeproj/project.pbxproj
grep -n 'ENABLE_APP_SANDBOX' DevSpace.xcodeproj/project.pbxproj
```

Expected: todas as ocorrências agora são `NO`.

- [ ] **Step 3: Confirmar que o app ainda compila**

Run: `xcodebuild -project DevSpace.xcodeproj -scheme DevSpace -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add DevSpace.xcodeproj/project.pbxproj
git commit -m "chore(app): desligar App Sandbox

O app precisa dar spawn no binário claude do usuário e um alvo sandboxed
não consegue executar binários fora do próprio bundle. Consequência:
distribuição por Developer ID + notarização, fora da Mac App Store."
```

---

## Ao fim deste plano

Existe: um pacote SPM testado que acha o `claude`, dá spawn nele, enquadra a saída e grava sessões reais em NDJSON; e um alvo de app pronto para receber a UI.

Não existe, por decisão: protocolo de controle, mapper, modelo de domínio do
transcript, store, UI.

Também não existe ainda, e tem dono no plano seguinte: o registro de pids para
varrer processos órfãos (spec §5.2). Ele só faz sentido quando houver um
gerenciador de sessões mantendo processos vivos — o `harness-probe` roda um
processo por vez e sai junto com ele.

O próximo plano (Etapas 3–4) se escreve **contra os fixtures das Tasks 4.4 e 4.5**, não contra especulação. Ele cobre `ControlProtocol`, `ClaudeEventMapper`, o modelo `Session`/`Segment`/`TranscriptEntry` e o `FileTranscriptStore`.
