# Protocolo de Controle (Etapa 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fazer o DevSpace conversar pelo protocolo de controle do Claude Code — receber pedidos de permissão, respondê-los, interromper e trocar o modo de permissão — e declarar o que o harness suporta.

**Architecture:** Um `ControlChannel` envolve o `ProcessTransport` e divide o fluxo de linhas em duas correntes: mensagens de conversa (que a Etapa 4 vai mapear) e quadros de controle. A saída correlaciona requests por `request_id`; a entrada entrega pedidos de permissão ao consumidor e devolve a decisão dele. Antes disso, os tipos que não têm nada de Claude migram para `HarnessCore`.

**Tech Stack:** Swift 6.4, SwiftPM, Swift Testing. Zero dependências externas.

**Spec:** `docs/superpowers/specs/2026-09-16-devspace-fundacao-design.md` (ver §4.1, §7.1 e §5.3)

**Achados que este plano consome:** `docs/superpowers/notes-2026-09-17-protocolo-observado.md` — contrato do protocolo verificado contra o CLI 2.1.236, incluindo a flag que o habilita.

## Global Constraints

- Swift tools 6.0; plataforma `.macOS(.v15)`. Concorrência estrita do Swift 6 em vigor.
- **Zero dependências externas** no `Package.swift`.
- Swift Testing (`import Testing`, `@Test`, `#expect`) — não XCTest.
- **Nenhum teste executa o `claude` real.** Use o fixture gravado e binários falsos via `/bin/sh`. Testes de integração, se houver, levam `.enabled(if: ProcessInfo.processInfo.environment["HARNESSKIT_INTEGRATION"] != nil)`.
- **Sem asserções de tempo de relógio.** Esta suíte evita flakes sensíveis a carga; use orçamentos injetados e `withTimeout` como guarda, nunca como afirmação.
- Estado atual a preservar: 61 testes, build limpo sem warnings, execução ~120 ms.
- Regra estrutural (spec §7.1): **se um tipo não menciona Claude e um segundo adaptador precisaria dele, ele mora em `HarnessCore`.**

---

## File Structure

| Arquivo | Responsabilidade |
|---|---|
| `Sources/HarnessCore/ProcessTransport.swift` | *(movido de ClaudeHarness)* spawn, stream, stdin, encerramento |
| `Sources/HarnessCore/CommandRunner.swift` | *(movido)* execução de comando, dreno dos dois pipes |
| `Sources/HarnessCore/HarnessInstallation.swift` | *(extraído de ClaudeDiscovery.swift)* binário + versão |
| `Sources/HarnessCore/HarnessCapabilities.swift` | o que um harness suporta; lido pela UI |
| `Sources/HarnessCore/JSONValue.swift` | valor JSON dinâmico, preserva inteiros |
| `Sources/ClaudeHarness/ControlFrames.swift` | envelopes e tipos do protocolo, `Codable` |
| `Sources/ClaudeHarness/ControlChannel.swift` | demultiplexação, correlação, resposta de permissão |
| `Sources/ClaudeHarness/ClaudeLaunch.swift` | monta a `Launch` do Claude Code e declara capabilities |
| `Sources/HarnessTestSupport/TestTimeout.swift` | *(movido)* `withTimeout`, usado por dois alvos de teste |

---

### Task 1: Mover os tipos neutros para HarnessCore

A spec §7.1 decidiu isto. `ProcessTransport`, `CommandRunner`/`SystemCommandRunner`/`CommandFailure` e `HarnessInstallation` não contêm nenhuma referência ao Claude, e um adaptador do Codex precisaria dos três.

**Files:**
- Move: `Sources/ClaudeHarness/ProcessTransport.swift` → `Sources/HarnessCore/ProcessTransport.swift`
- Move: `Sources/ClaudeHarness/CommandRunner.swift` → `Sources/HarnessCore/CommandRunner.swift`
- Create: `Sources/HarnessCore/HarnessInstallation.swift` (extraído de `ClaudeDiscovery.swift`)
- Modify: `Sources/ClaudeHarness/ClaudeDiscovery.swift` (remover `HarnessInstallation`, adicionar `import HarnessCore`)
- Move: `Tests/ClaudeHarnessTests/ProcessTransportTests.swift` → `Tests/HarnessCoreTests/`
- Move: `Tests/ClaudeHarnessTests/CommandRunnerTests.swift` → `Tests/HarnessCoreTests/`
- Move: `Tests/ClaudeHarnessTests/TestTimeout.swift` → `Sources/HarnessTestSupport/TestTimeout.swift`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: nada.
- Produces: os mesmos tipos, agora em `HarnessCore`. Assinaturas **inalteradas**: `ProcessTransport.Launch(executable:arguments:workingDirectory:environment:)`, `start(_:) throws -> AsyncThrowingStream<Data, Error>`, `write(_:) throws`, `endInput()`, `terminate() async`, `standardError: String`, `terminationStatus: Int32?`, `TransportError.notRunning` / `.alreadyStarted`, `init(framingLimit:terminationGracePeriod:killGracePeriod:)`. Também `CommandRunner`, `SystemCommandRunner`, `CommandFailure(exitCode:stderr:)`, `HarnessInstallation(executable:version:)`. As Tasks 4–6 usam todas elas.

- [ ] **Step 1: Criar o alvo de apoio a testes e mover o `TestTimeout`**

`withTimeout` é usado hoje por `ProcessTransportTests` e `CommandRunnerTests`, que vão para `HarnessCoreTests`, e será usado pelos testes de controle, que ficam em `ClaudeHarnessTests`. Dois alvos de teste precisam dele, então ele vira um alvo próprio em vez de ser duplicado.

```bash
cd Packages/HarnessKit
mkdir -p Sources/HarnessTestSupport
git mv Tests/ClaudeHarnessTests/TestTimeout.swift Sources/HarnessTestSupport/TestTimeout.swift
```

Tornar `withTimeout` e `TimedOut` públicos (hoje são internos/privados ao arquivo):

```swift
public struct TimedOut: Error, Equatable {
    public init() {}
}

public func withTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
```

Mantenha `OnceContinuation` privado — é detalhe interno.

- [ ] **Step 2: Mover os arquivos de fonte e de teste**

```bash
cd Packages/HarnessKit
git mv Sources/ClaudeHarness/ProcessTransport.swift Sources/HarnessCore/ProcessTransport.swift
git mv Sources/ClaudeHarness/CommandRunner.swift    Sources/HarnessCore/CommandRunner.swift
git mv Tests/ClaudeHarnessTests/ProcessTransportTests.swift Tests/HarnessCoreTests/ProcessTransportTests.swift
git mv Tests/ClaudeHarnessTests/CommandRunnerTests.swift    Tests/HarnessCoreTests/CommandRunnerTests.swift
```

Em `Sources/HarnessCore/ProcessTransport.swift`, **remova** a linha `import HarnessCore` (agora ele É o HarnessCore). Nos dois arquivos de teste movidos, troque `@testable import ClaudeHarness` por `@testable import HarnessCore` e acrescente `import HarnessTestSupport`.

- [ ] **Step 3: Extrair `HarnessInstallation` para arquivo próprio**

Recorte o tipo de `Sources/ClaudeHarness/ClaudeDiscovery.swift` e crie `Sources/HarnessCore/HarnessInstallation.swift` com ele **na íntegra, incluindo os comentários de doc**:

```swift
/// Onde um harness está instalado e em que versão.
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
```

Em `ClaudeDiscovery.swift`, acrescente `import HarnessCore` no topo.

- [ ] **Step 4: Atualizar o manifesto**

```swift
        .target(name: "HarnessCore"),
        .target(name: "HarnessTestSupport"),
        .testTarget(
            name: "HarnessCoreTests",
            dependencies: ["HarnessCore", "HarnessTestSupport"]
        ),
        .target(name: "ClaudeHarness", dependencies: ["HarnessCore"]),
        .testTarget(
            name: "ClaudeHarnessTests",
            dependencies: ["ClaudeHarness", "HarnessCore", "HarnessTestSupport"],
            resources: [.copy("Fixtures")]
        ),
```

`HarnessTestSupport` **não** entra em `products` — é detalhe interno do pacote.

- [ ] **Step 5: Escrever o teste que prova a mudança**

O ponto da realocação é que o transporte seja alcançável sem importar `ClaudeHarness`. Um teste em `HarnessCoreTests` que usa `ProcessTransport` prova isso por construção: se o tipo ainda estivesse em `ClaudeHarness`, o arquivo não compila.

Crie `Tests/HarnessCoreTests/ModuleBoundaryTests.swift`:

```swift
import Testing
import Foundation
import HarnessCore

// Este alvo NÃO depende de ClaudeHarness. Se algum destes tipos voltar para
// lá, este arquivo deixa de compilar — que é exatamente o alarme desejado.
@Test func theGenericTypesLiveInHarnessCore() async throws {
    let transport = ProcessTransport()
    let stream = try await transport.start(ProcessTransport.Launch(
        executable: "/bin/sh",
        arguments: ["-c", #"printf '{"a":1}\n'"#],
        workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
    ))
    var lines: [String] = []
    for try await line in stream { lines.append(String(decoding: line, as: UTF8.self)) }
    #expect(lines == [#"{"a":1}"#])

    let install = HarnessInstallation(executable: "/usr/bin/true", version: "1.0.0")
    #expect(install.executable == "/usr/bin/true")

    let failure = CommandFailure(exitCode: 3, stderr: "boom")
    #expect(failure.exitCode == 3)
}
```

- [ ] **Step 6: Compilar e rodar a suíte inteira**

Run: `cd Packages/HarnessKit && swift build && swift test`
Expected: build limpo sem warnings; 62 testes (os 61 de antes mais `theGenericTypesLiveInHarnessCore`), 61 passando + 1 pulado por ambiente.

Se algum teste movido falhar, a causa quase certa é import faltando — não altere a lógica de nenhum teste nesta task.

- [ ] **Step 7: Confirmar que `ClaudeHarness` encolheu para o que é do Claude**

```bash
cd Packages/HarnessKit && ls Sources/ClaudeHarness/
```
Expected: apenas `ClaudeDiscovery.swift`.

```bash
grep -ril 'claude' Sources/HarnessCore/ | grep -v '^$' || echo "HarnessCore não menciona claude"
```
Expected: nenhuma ocorrência.

- [ ] **Step 8: Commit**

```bash
git add Packages/HarnessKit
git commit -m "refactor(harnesskit): tipos neutros vão para HarnessCore

ProcessTransport, CommandRunner e HarnessInstallation não têm nada de Claude e
um segundo adaptador precisaria dos três. Ficavam em ClaudeHarness porque a
spec §7 mandava; a §7.1 reverteu isso.

TestTimeout vira alvo próprio porque dois alvos de teste passam a precisar dele."
```

---

### Task 2: `JSONValue` — valor JSON dinâmico que preserva inteiros

**Files:**
- Create: `Sources/HarnessCore/JSONValue.swift`
- Test: `Tests/HarnessCoreTests/JSONValueTests.swift`

**Interfaces:**
- Consumes: nada.
- Produces: `public enum JSONValue: Sendable, Equatable, Codable` com casos `.null`, `.bool(Bool)`, `.int(Int)`, `.double(Double)`, `.string(String)`, `.array([JSONValue])`, `.object([String: JSONValue])`. As Tasks 3, 5 e 6 usam este tipo.

**Por que inteiro e ponto flutuante são casos separados:** a Task 5 devolve o `input` da ferramenta de volta ao CLI ao permitir uma chamada. Se `{"count":1}` voltasse como `{"count":1.0}`, a chamada mudaria. Um único caso `.number(Double)` faria exatamente isso.

- [ ] **Step 1: Escrever os testes que falham**

```swift
import Testing
import Foundation
@testable import HarnessCore

private func roundTrip(_ json: String) throws -> String {
    let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

@Test func decodesEachScalarKind() throws {
    let v = try JSONDecoder().decode(JSONValue.self, from: Data(#"""
    {"n":null,"b":true,"i":42,"d":1.5,"s":"oi"}
    """#.utf8))
    #expect(v == .object([
        "n": .null, "b": .bool(true), "i": .int(42),
        "d": .double(1.5), "s": .string("oi"),
    ]))
}

@Test func preservesIntegersAcrossARoundTrip() throws {
    // O caso que motiva o tipo: um inteiro não pode virar ponto flutuante,
    // porque o input da ferramenta é devolvido ao CLI ao permitir a chamada.
    #expect(try roundTrip(#"{"count":1}"#) == #"{"count":1}"#)
    #expect(try roundTrip(#"{"count":0}"#) == #"{"count":0}"#)
    #expect(try roundTrip(#"{"count":-7}"#) == #"{"count":-7}"#)
}

@Test func preservesFractionalNumbers() throws {
    #expect(try roundTrip(#"{"ratio":1.5}"#) == #"{"ratio":1.5}"#)
}

@Test func handlesNestingAndArrays() throws {
    let json = #"{"a":[1,{"b":["x",null,false]}]}"#
    #expect(try roundTrip(json) == json)
}

@Test func roundTripsTheRealPermissionRequestInput() throws {
    // O input exato que o CLI mandou no fixture gravado.
    let json = #"{"content":"ok","file_path":"/private/tmp/probe-scratch/prova.txt"}"#
    #expect(try roundTrip(json) == json)
}

@Test func subscriptReadsObjectMembers() throws {
    let v = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"a":{"b":"c"}}"#.utf8))
    #expect(v["a"]?["b"] == .string("c"))
    #expect(v["ausente"] == nil)
}

@Test func stringAccessorReturnsNilForOtherKinds() throws {
    #expect(JSONValue.string("oi").stringValue == "oi")
    #expect(JSONValue.int(1).stringValue == nil)
}
```

- [ ] **Step 2: Rodar e confirmar que falham**

Run: `cd Packages/HarnessKit && swift test --filter JSONValue`
Expected: FAIL — `cannot find 'JSONValue' in scope`.

- [ ] **Step 3: Implementar**

```swift
import Foundation

/// Um valor JSON qualquer, preservado sem esquema.
///
/// Inteiro e ponto flutuante são casos distintos de propósito: o `input` de uma
/// ferramenta é devolvido ao CLI quando o usuário permite a chamada, e um
/// `{"count":1}` que voltasse como `{"count":1.0}` mudaria a chamada.
public enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

public extension JSONValue {
    subscript(key: String) -> JSONValue? {
        guard case .object(let members) = self else { return nil }
        return members[key]
    }

    var stringValue: String? {
        guard case .string(let s) = self else { return nil }
        return s
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let o) = self else { return nil }
        return o
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let a) = self else { return nil }
        return a
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let b = try? container.decode(Bool.self) { self = .bool(b); return }
        // Int antes de Double: a ordem é o que preserva a inteireza.
        if let i = try? container.decode(Int.self) { self = .int(i); return }
        if let d = try? container.decode(Double.self) { self = .double(d); return }
        if let s = try? container.decode(String.self) { self = .string(s); return }
        if let a = try? container.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? container.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(
            in: container, debugDescription: "valor JSON não reconhecido"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }
}
```

- [ ] **Step 4: Rodar e confirmar que passam**

Run: `cd Packages/HarnessKit && swift test --filter JSONValue`
Expected: PASS, 7 testes.

Se `preservesIntegersAcrossARoundTrip` falhar com `{"count":1}` virando `{"count":1.0}`, a ordem das tentativas no `init(from:)` está errada — `Int` tem que vir antes de `Double`.

- [ ] **Step 5: Commit**

```bash
git add Packages/HarnessKit
git commit -m "feat(harnesskit): JSONValue preservando inteiros no round-trip"
```

---

### Task 3: Tipos do protocolo de controle

**Files:**
- Create: `Sources/ClaudeHarness/ControlFrames.swift`
- Test: `Tests/ClaudeHarnessTests/ControlFramesTests.swift`

**Interfaces:**
- Consumes: `JSONValue` (Task 2).
- Produces: `ControlFrame` (enum de classificação), `PermissionRequest`, `PermissionSuggestion`, `PermissionDecision`, `OutboundControlRequest`, `ControlResponseResult`. As Tasks 4, 5 e 6 usam todos.

O contrato abaixo foi verificado contra o CLI 2.1.236 e está gravado em `Tests/ClaudeHarnessTests/Fixtures/permission-request.ndjson`.

- [ ] **Step 1: Escrever os testes que falham**

```swift
import Testing
import Foundation
import HarnessCore
@testable import ClaudeHarness

private func fixtureLines(_ name: String) throws -> [Data] {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "ndjson"))
    return try String(contentsOf: url, encoding: .utf8)
        .split(separator: "\n").filter { !$0.isEmpty }.map { Data($0.utf8) }
}

@Test func classifiesAConversationLineAsConversation() throws {
    let line = Data(#"{"type":"assistant","message":{"role":"assistant"}}"#.utf8)
    #expect(ControlFrame.classify(line) == .conversation)
}

@Test func classifiesAControlResponseByItsRequestID() throws {
    let line = Data(#"""
    {"type":"control_response","response":{"subtype":"success","request_id":"init-1","response":{"commands":[]}}}
    """#.utf8)
    guard case .response(let id, let result) = ControlFrame.classify(line) else {
        Issue.record("esperava .response"); return
    }
    #expect(id == "init-1")
    #expect(result.isSuccess)
}

@Test func classifiesAnErrorResponse() throws {
    let line = Data(#"""
    {"type":"control_response","response":{"subtype":"error","request_id":"x","error":"deu ruim"}}
    """#.utf8)
    guard case .response(_, let result) = ControlFrame.classify(line) else {
        Issue.record("esperava .response"); return
    }
    #expect(!result.isSuccess)
    #expect(result.errorMessage == "deu ruim")
}

@Test func parsesTheRealPermissionRequestFromTheFixture() throws {
    let frames = try fixtureLines("permission-request").map(ControlFrame.classify)
    let requests = frames.compactMap { frame -> PermissionRequest? in
        if case .permissionRequest(let r) = frame { return r }
        return nil
    }
    #expect(requests.count == 1)
    let r = try #require(requests.first)
    #expect(r.toolName == "Write")
    #expect(r.displayName == "Write")
    #expect(r.description == "prova.txt")
    #expect(r.toolUseID == "toolu_01MnTatUeYfz3cMti4VXq4z8")
    #expect(r.input["content"] == .string("ok"))
    #expect(r.suggestions.count == 1)
    #expect(r.suggestions.first?.type == "setMode")
    #expect(r.suggestions.first?.mode == "acceptEdits")
    #expect(r.suggestions.first?.destination == "session")
    #expect(!r.id.isEmpty)
}

@Test func anUnknownControlSubtypeIsPreservedNotRejected() throws {
    // Spec §5.4: um subtipo desconhecido nunca é erro — degrada, não quebra.
    let line = Data(#"""
    {"type":"control_request","request_id":"z","request":{"subtype":"coisa_nova","x":1}}
    """#.utf8)
    guard case .unknownControl(let id, let raw) = ControlFrame.classify(line) else {
        Issue.record("esperava .unknownControl"); return
    }
    #expect(id == "z")
    #expect(raw["request"]?["subtype"] == .string("coisa_nova"))
}

@Test func malformedJSONIsTreatedAsConversationNotAsAFailure() throws {
    // O mapper da Etapa 4 decide o que fazer; o canal de controle não julga.
    #expect(ControlFrame.classify(Data("nao sou json".utf8)) == .conversation)
}

@Test func encodesAnAllowDecisionInTheShapeTheCLIAccepts() throws {
    let decision = PermissionDecision.allow(updatedInput: .object(["a": .int(1)]))
    let data = try decision.responseData(requestID: "req-9")
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(decoded["type"] == .string("control_response"))
    #expect(decoded["response"]?["subtype"] == .string("success"))
    #expect(decoded["response"]?["request_id"] == .string("req-9"))
    #expect(decoded["response"]?["response"]?["behavior"] == .string("allow"))
    #expect(decoded["response"]?["response"]?["updatedInput"]?["a"] == .int(1))
}

@Test func encodesADenyDecision() throws {
    let decision = PermissionDecision.deny(message: "não", interrupt: false)
    let data = try decision.responseData(requestID: "req-9")
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(decoded["response"]?["response"]?["behavior"] == .string("deny"))
    #expect(decoded["response"]?["response"]?["message"] == .string("não"))
    #expect(decoded["response"]?["response"]?["interrupt"] == .bool(false))
}

@Test func encodesAnOutboundRequestWithItsID() throws {
    let request = OutboundControlRequest.interrupt
    let data = try request.requestData(requestID: "out-1")
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(decoded["type"] == .string("control_request"))
    #expect(decoded["request_id"] == .string("out-1"))
    #expect(decoded["request"]?["subtype"] == .string("interrupt"))
}

@Test func encodesSetPermissionModeWithItsMode() throws {
    let data = try OutboundControlRequest.setPermissionMode("acceptEdits")
        .requestData(requestID: "out-2")
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(decoded["request"]?["subtype"] == .string("set_permission_mode"))
    #expect(decoded["request"]?["mode"] == .string("acceptEdits"))
}
```

- [ ] **Step 2: Rodar e confirmar que falham**

Run: `cd Packages/HarnessKit && swift test --filter ControlFrames`
Expected: FAIL — `cannot find 'ControlFrame' in scope`.

- [ ] **Step 3: Implementar**

```swift
import Foundation
import HarnessCore

/// O que uma linha do stdout do harness é, do ponto de vista do canal de controle.
public enum ControlFrame: Equatable, Sendable {
    /// Mensagem de conversa — o canal não a interpreta; a Etapa 4 mapeia.
    case conversation
    /// O harness está pedindo permissão para usar uma ferramenta.
    case permissionRequest(PermissionRequest)
    /// Resposta a um request que nós enviamos.
    case response(requestID: String, ControlResponseResult)
    /// Quadro de controle de subtipo que não conhecemos. Spec §5.4: preservar,
    /// não falhar.
    case unknownControl(requestID: String, raw: JSONValue)

    public static func classify(_ line: Data) -> ControlFrame {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: line),
              let type = value["type"]?.stringValue
        else { return .conversation }

        switch type {
        case "control_request":
            let id = value["request_id"]?.stringValue ?? ""
            guard let request = value["request"],
                  request["subtype"]?.stringValue == "can_use_tool",
                  let parsed = PermissionRequest(id: id, request: request)
            else { return .unknownControl(requestID: id, raw: value) }
            return .permissionRequest(parsed)

        case "control_response":
            guard let response = value["response"] else { return .conversation }
            let id = response["request_id"]?.stringValue ?? ""
            if response["subtype"]?.stringValue == "error" {
                return .response(requestID: id,
                                 .failure(response["error"]?.stringValue ?? "erro sem mensagem"))
            }
            return .response(requestID: id, .success(response["response"] ?? .null))

        default:
            return .conversation
        }
    }
}

public enum ControlResponseResult: Equatable, Sendable {
    case success(JSONValue)
    case failure(String)

    public var isSuccess: Bool { if case .success = self { return true }; return false }
    public var errorMessage: String? { if case .failure(let m) = self { return m }; return nil }
    public var payload: JSONValue? { if case .success(let p) = self { return p }; return nil }
}

/// Um pedido de permissão vindo do harness.
public struct PermissionRequest: Equatable, Sendable {
    public let id: String
    public let toolName: String
    public let displayName: String?
    public let description: String?
    public let input: JSONValue
    public let toolUseID: String?
    /// Regras que o próprio harness sugere — material direto para os botões do
    /// diálogo ("permitir sempre nesta sessão") em vez de inventarmos os nossos.
    public let suggestions: [PermissionSuggestion]

    init?(id: String, request: JSONValue) {
        guard let toolName = request["tool_name"]?.stringValue else { return nil }
        self.id = id
        self.toolName = toolName
        self.displayName = request["display_name"]?.stringValue
        self.description = request["description"]?.stringValue
        self.input = request["input"] ?? .null
        self.toolUseID = request["tool_use_id"]?.stringValue
        self.suggestions = (request["permission_suggestions"]?.arrayValue ?? [])
            .compactMap(PermissionSuggestion.init(raw:))
    }
}

public struct PermissionSuggestion: Equatable, Sendable {
    public let type: String
    public let mode: String?
    public let destination: String?
    public let behavior: String?
    /// Payload original preservado — nem todo campo de sugestão é conhecido.
    public let raw: JSONValue

    init?(raw: JSONValue) {
        guard let type = raw["type"]?.stringValue else { return nil }
        self.type = type
        self.mode = raw["mode"]?.stringValue
        self.destination = raw["destination"]?.stringValue
        self.behavior = raw["behavior"]?.stringValue
        self.raw = raw
    }
}

public enum PermissionDecision: Equatable, Sendable {
    case allow(updatedInput: JSONValue?)
    case deny(message: String, interrupt: Bool)

    /// A linha NDJSON a escrever no stdin do harness.
    public func responseData(requestID: String) throws -> Data {
        let body: JSONValue
        switch self {
        case .allow(let updatedInput):
            var members: [String: JSONValue] = ["behavior": .string("allow")]
            if let updatedInput { members["updatedInput"] = updatedInput }
            body = .object(members)
        case .deny(let message, let interrupt):
            body = .object([
                "behavior": .string("deny"),
                "message": .string(message),
                "interrupt": .bool(interrupt),
            ])
        }
        let envelope = JSONValue.object([
            "type": .string("control_response"),
            "response": .object([
                "subtype": .string("success"),
                "request_id": .string(requestID),
                "response": body,
            ]),
        ])
        return try JSONEncoder().encode(envelope)
    }
}

/// Requests que nós enviamos ao harness.
public enum OutboundControlRequest: Equatable, Sendable {
    case initialize
    case interrupt
    case setPermissionMode(String)
    case setModel(String?)

    var subtype: String {
        switch self {
        case .initialize: return "initialize"
        case .interrupt: return "interrupt"
        case .setPermissionMode: return "set_permission_mode"
        case .setModel: return "set_model"
        }
    }

    public func requestData(requestID: String) throws -> Data {
        var request: [String: JSONValue] = ["subtype": .string(subtype)]
        switch self {
        case .initialize, .interrupt:
            break
        case .setPermissionMode(let mode):
            request["mode"] = .string(mode)
        case .setModel(let model):
            request["model"] = model.map(JSONValue.string) ?? .null
        }
        let envelope = JSONValue.object([
            "type": .string("control_request"),
            "request_id": .string(requestID),
            "request": .object(request),
        ])
        return try JSONEncoder().encode(envelope)
    }
}
```

- [ ] **Step 4: Rodar e confirmar que passam**

Run: `cd Packages/HarnessKit && swift test --filter ControlFrames`
Expected: PASS, 10 testes.

Se `parsesTheRealPermissionRequestFromTheFixture` não achar o arquivo, confirme que `Package.swift` ainda tem `resources: [.copy("Fixtures")]` em `ClaudeHarnessTests`.

- [ ] **Step 5: Commit**

```bash
git add Packages/HarnessKit
git commit -m "feat(harnesskit): tipos do protocolo de controle, validados contra o fixture real"
```

---

### Task 4: `ControlChannel` — demultiplexação e requests de saída

**Files:**
- Create: `Sources/ClaudeHarness/ControlChannel.swift`
- Test: `Tests/ClaudeHarnessTests/ControlChannelTests.swift`

**Interfaces:**
- Consumes: `ProcessTransport` (Task 1, estendido com `writeSync` no Step 3 desta task), `JSONValue` (Task 2), `ControlFrame`/`OutboundControlRequest`/`ControlResponseResult` (Task 3), `withTimeout` (Task 1).
- Produces: `public actor ControlChannel` com `init(transport:requestTimeout:)`, `func start(_:) throws -> AsyncThrowingStream<ChannelOutput, Error>`, `func send(_:) async throws -> JSONValue`, `func writeTurn(_:) async throws`, `func endInput() async`, `func stop() async`; e `public enum ChannelOutput { case conversation(Data); case permissionRequest(PermissionRequest) }`. A Task 5 acrescenta `respond(to:with:)`; a Task 6 consome tudo.

- [ ] **Step 1: Escrever os testes que falham**

O harness falso é `/bin/sh` — responde a um `control_request` lendo o `request_id` com `sed` e devolvendo um `control_response`.

```swift
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
/// ecoando o request_id. Linhas que não são de controle são ignoradas.
private let echoingResponder = #"""
while IFS= read -r l; do
  case "$l" in
    *'"type":"control_request"'*)
      id=$(printf '%s' "$l" | sed -n 's/.*"request_id":"\([^"]*\)".*/\1/p')
      printf '{"type":"control_response","response":{"subtype":"success","request_id":"%s","response":{"ok":true}}}\n' "$id"
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

    async let first = channel.send(.interrupt)
    async let second = channel.send(.setPermissionMode("acceptEdits"))
    let results = try await withTimeout(seconds: 3) { try await [first, second] }
    #expect(results.count == 2)
    #expect(results.allSatisfy { $0["ok"] == .bool(true) })
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

    await #expect(throws: ControlChannel.ChannelError.timedOut) {
        _ = try await channel.send(.interrupt)
    }
    await channel.stop()
}
```

- [ ] **Step 2: Rodar e confirmar que falham**

Run: `cd Packages/HarnessKit && swift test --filter ControlChannel`
Expected: FAIL — `cannot find 'ControlChannel' in scope`.

- [ ] **Step 3: Acrescentar `writeSync` ao `ProcessTransport`**

`ProcessTransport.write(_:)` é membro de ator e exige `await`. O `send(_:)` da
próxima etapa precisa escrever **sem suspender**, porque suspender entre
registrar o pendente e escrever abre a janela em que a resposta chega antes do
registro e a correlação se perde. Uma escrita `nonisolated` sobre um handle
protegido por lock fecha essa janela.

Em `Sources/HarnessCore/ProcessTransport.swift`, junto aos outros campos do ator:

```swift
import Synchronization

// ... dentro do ator, junto de `standardInput`:
private let syncStandardInput = Mutex<FileHandle?>(nil)
```

Atribua em `start(_:)` onde `self.standardInput` já é atribuído:

```swift
        syncStandardInput.withLock { $0 = stdin.fileHandleForWriting }
```

e limpe em `endInput()`, junto do fechamento existente:

```swift
        syncStandardInput.withLock { $0 = nil }
```

E o método em si:

```swift
    /// Escrita sem suspensão, para chamadores que precisam registrar estado
    /// antes de a resposta poder chegar. Mesmo contrato de `write(_:)`.
    nonisolated public func writeSync(_ line: Data) throws {
        guard let handle = syncStandardInput.withLock({ $0 }) else {
            throw TransportError.notRunning
        }
        try handle.write(contentsOf: line + Data("\n".utf8))
    }
```

Se `Synchronization.Mutex` não resolver no seu toolchain, use uma classe
`@unchecked Sendable` com `NSLock`, no mesmo formato de `StreamIO` — o
requisito é apenas que a leitura seja `nonisolated` e sincronizada.

Acrescente o teste em `Tests/HarnessCoreTests/ProcessTransportTests.swift`:

```swift
@Test func writeSyncReachesTheChildWithoutSuspending() async throws {
    let transport = ProcessTransport()
    let stream = try await transport.start(shellLaunch(#"while read -r l; do printf '{"eco":%s}\n' "$l"; done"#))
    try transport.writeSync(Data(#"{"a":1}"# .utf8))
    await transport.endInput()

    var received: [String] = []
    for try await line in stream { received.append(String(decoding: line, as: UTF8.self)) }
    #expect(received == [#"{"eco":{"a":1}}"#])
}

@Test func writeSyncFailsAfterInputIsClosed() async throws {
    let transport = ProcessTransport()
    let stream = try await transport.start(shellLaunch("cat > /dev/null"))
    await transport.endInput()
    #expect(throws: ProcessTransport.TransportError.notRunning) {
        try transport.writeSync(Data("{}".utf8))
    }
    for try await _ in stream {}
}
```

Run: `cd Packages/HarnessKit && swift test --filter ProcessTransport`
Expected: PASS, incluindo os dois novos.

- [ ] **Step 4: Implementar o `ControlChannel`**

```swift
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
        case notStarted
        case timedOut
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
                    await self?.failAllPending(.notStarted)
                    continuation.finish()
                } catch {
                    await self?.failAllPending(.notStarted)
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

    private func failAllPending(_ error: ChannelError) {
        let waiting = pending
        pending.removeAll()
        for (_, continuation) in waiting { continuation.resume(throwing: error) }
    }

    /// Envia um request de controle e espera a resposta correlacionada.
    public func send(_ request: OutboundControlRequest) async throws -> JSONValue {
        guard started else { throw ChannelError.notStarted }
        nextRequestNumber += 1
        let id = "devspace-\(nextRequestNumber)"
        let data = try request.requestData(requestID: id)

        let timeout = Task { [requestTimeout] in
            try? await Task.sleep(for: requestTimeout)
            if !Task.isCancelled { await self.timeOut(id) }
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

    public func stop() async {
        failAllPending(.notStarted)
        await transport.terminate()
    }
}
```

- [ ] **Step 5: Rodar e confirmar que passam**

Run: `cd Packages/HarnessKit && swift test --filter ControlChannel`
Expected: PASS, 6 testes. O teste de timeout deve terminar em menos de 200 ms — se demorar segundos, o prazo injetado não está sendo usado.

- [ ] **Step 6: Rodar a suíte inteira**

Run: `cd Packages/HarnessKit && swift test`
Expected: tudo verde, sem regressão nos testes do transporte.

- [ ] **Step 7: Commit**

```bash
git add Packages/HarnessKit
git commit -m "feat(harnesskit): ControlChannel com demultiplexação e correlação por request_id"
```

---

### Task 5: Responder pedidos de permissão

**Files:**
- Modify: `Sources/ClaudeHarness/ControlChannel.swift`
- Test: `Tests/ClaudeHarnessTests/PermissionRoundTripTests.swift`

**Interfaces:**
- Consumes: tudo das Tasks 3 e 4.
- Produces: `ControlChannel.respond(to:with:) throws` (membro de ator — chamado com `await` de fora) recebendo o `id` do pedido (`String`) e um `PermissionDecision`. A Task 6 usa.

- [ ] **Step 1: Escrever os testes que falham**

O harness falso pede permissão, lê a resposta e imprime o que decidiu — assim o teste observa a decisão pelo lado do harness, não só pelo nosso.

```swift
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

    var request: PermissionRequest?
    for try await output in stream {
        if case .permissionRequest(let r) = output {
            request = r
            try await channel.respond(to: r.id, with: .allow(updatedInput: nil))
        }
    }
    let r = try #require(request)
    #expect(r.toolName == "Write")
    #expect(r.toolUseID == "toolu_1")
    #expect(r.suggestions.first?.mode == "acceptEdits")
}

@Test func allowIsWhatTheHarnessReceives() async throws {
    let channel = ControlChannel(transport: ProcessTransport())
    let stream = try await channel.start(launch(askingHarness))

    var decided: String?
    for try await output in stream {
        switch output {
        case .permissionRequest(let r):
            try await channel.respond(to: r.id, with: .allow(updatedInput: nil))
        case .conversation(let data):
            let v = try JSONDecoder().decode(JSONValue.self, from: data)
            if let d = v["decidiu"]?.stringValue { decided = d }
        }
    }
    #expect(decided == "allow")
}

@Test func denyIsWhatTheHarnessReceives() async throws {
    let channel = ControlChannel(transport: ProcessTransport())
    let stream = try await channel.start(launch(askingHarness))

    var decided: String?
    for try await output in stream {
        switch output {
        case .permissionRequest(let r):
            try await channel.respond(to: r.id, with: .deny(message: "não", interrupt: false))
        case .conversation(let data):
            let v = try JSONDecoder().decode(JSONValue.self, from: data)
            if let d = v["decidiu"]?.stringValue { decided = d }
        }
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

    var echoed: JSONValue?
    for try await output in stream {
        switch output {
        case .permissionRequest(let r):
            try await channel.respond(to: r.id, with: .allow(updatedInput: r.input))
        case .conversation(let data):
            let v = try JSONDecoder().decode(JSONValue.self, from: data)
            if let e = v["eco"] { echoed = e }
        }
    }
    #expect(echoed?["count"] == .int(1))
}
```

- [ ] **Step 2: Rodar e confirmar que falham**

Run: `cd Packages/HarnessKit && swift test --filter PermissionRoundTrip`
Expected: FAIL — `value of type 'ControlChannel' has no member 'respond'`.

- [ ] **Step 3: Implementar**

Acrescente ao `ControlChannel`:

```swift
    /// Responde a um pedido de permissão.
    ///
    /// Não há resposta a esperar: a decisão é o fim da troca. Se o consumidor
    /// nunca responder, o harness fica bloqueado — é por isso que o pedido
    /// carrega o `id` e não um callback.
    public func respond(to requestID: String, with decision: PermissionDecision) throws {
        guard started else { throw ChannelError.notStarted }
        try transport.writeSync(try decision.responseData(requestID: requestID))
    }
```

- [ ] **Step 4: Rodar e confirmar que passam**

Run: `cd Packages/HarnessKit && swift test --filter PermissionRoundTrip`
Expected: PASS, 4 testes.

- [ ] **Step 5: Commit**

```bash
git add Packages/HarnessKit
git commit -m "feat(harnesskit): responder pedidos de permissão pelo canal de controle"
```

---

### Task 6: `HarnessCapabilities` e o lançamento do Claude Code

**Files:**
- Create: `Sources/HarnessCore/HarnessCapabilities.swift`
- Create: `Sources/ClaudeHarness/ClaudeLaunch.swift`
- Test: `Tests/HarnessCoreTests/HarnessCapabilitiesTests.swift`
- Test: `Tests/ClaudeHarnessTests/ClaudeLaunchTests.swift`

**Interfaces:**
- Consumes: `HarnessInstallation` (Task 1), `ProcessTransport.Launch` (Task 1).
- Produces: `HarnessCapabilities` e `ClaudeLaunch.make(...)`.

**O achado que esta task materializa:** o CLI só roteia permissões pelo protocolo de controle quando recebe `--permission-prompt-tool stdio`. A flag **não aparece em `claude --help`** — foi encontrada no código do binário e no SDK oficial. Sem ela, o CLI decide sozinho e nenhum `can_use_tool` chega.

- [ ] **Step 1: Escrever os testes que falham**

```swift
// Tests/HarnessCoreTests/HarnessCapabilitiesTests.swift
import Testing
import HarnessCore

@Test func capabilitiesDefaultToTheConservativeAnswer() {
    // Um harness novo não suporta nada até declarar que suporta. A UI esconde
    // o que não foi declarado, em vez de oferecer botões que falham.
    let c = HarnessCapabilities()
    #expect(!c.routesPermissionRequests)
    #expect(!c.canInterrupt)
    #expect(!c.canSetPermissionMode)
    #expect(!c.canSetModelInSession)
    #expect(!c.canResumeSession)
    #expect(!c.canForkSession)
}

@Test func capabilitiesAreValuesAndCompareByContent() {
    let a = HarnessCapabilities(canInterrupt: true)
    let b = HarnessCapabilities(canInterrupt: true)
    #expect(a == b)
    #expect(a != HarnessCapabilities())
}
```

```swift
// Tests/ClaudeHarnessTests/ClaudeLaunchTests.swift
import Testing
import Foundation
import HarnessCore
@testable import ClaudeHarness

private let install = HarnessInstallation(executable: "/opt/homebrew/bin/claude", version: "2.1.236")
private let cwd = URL(fileURLWithPath: "/tmp/scratch")
private let session = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

@Test func theLaunchCarriesTheFlagThatEnablesPermissionRouting() {
    let launch = ClaudeLaunch.make(installation: install, workingDirectory: cwd, sessionID: session)
    let args = launch.arguments
    let i = try! #require(args.firstIndex(of: "--permission-prompt-tool"))
    #expect(args[args.index(after: i)] == "stdio")
}

@Test func theLaunchUsesTheStreamingProtocolInBothDirections() {
    let args = ClaudeLaunch.make(installation: install, workingDirectory: cwd, sessionID: session).arguments
    #expect(args.contains("-p"))
    for pair in [("--output-format", "stream-json"), ("--input-format", "stream-json")] {
        let i = try! #require(args.firstIndex(of: pair.0))
        #expect(args[args.index(after: i)] == pair.1)
    }
    #expect(args.contains("--verbose"))
    #expect(args.contains("--include-partial-messages"))
}

@Test func theSessionIDIsOursAndLowercased() {
    let args = ClaudeLaunch.make(installation: install, workingDirectory: cwd, sessionID: session).arguments
    let i = try! #require(args.firstIndex(of: "--session-id"))
    #expect(args[args.index(after: i)] == "11111111-2222-3333-4444-555555555555")
}

@Test func resumingPassesTheHarnessSessionID() {
    let previous = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!
    let args = ClaudeLaunch.make(installation: install, workingDirectory: cwd,
                                 sessionID: session, resuming: previous).arguments
    let i = try! #require(args.firstIndex(of: "--resume"))
    #expect(args[args.index(after: i)] == "99999999-8888-7777-6666-555555555555")
}

@Test func notResumingOmitsTheFlagEntirely() {
    let args = ClaudeLaunch.make(installation: install, workingDirectory: cwd, sessionID: session).arguments
    #expect(!args.contains("--resume"))
}

@Test func theLaunchRunsInTheRequestedDirectory() {
    let launch = ClaudeLaunch.make(installation: install, workingDirectory: cwd, sessionID: session)
    #expect(launch.workingDirectory == cwd)
    #expect(launch.executable == "/opt/homebrew/bin/claude")
}

@Test func theEnvironmentAnnouncesDevSpaceAsTheEntrypoint() {
    let launch = ClaudeLaunch.make(installation: install, workingDirectory: cwd, sessionID: session)
    #expect(launch.environment["CLAUDE_CODE_ENTRYPOINT"] == "devspace")
}

@Test func claudeCodeDeclaresWhatItSupports() {
    let c = ClaudeLaunch.capabilities(for: install)
    #expect(c.routesPermissionRequests)
    #expect(c.canInterrupt)
    #expect(c.canSetPermissionMode)
    #expect(c.canResumeSession)
    #expect(c.canForkSession)
}
```

- [ ] **Step 2: Rodar e confirmar que falham**

Run: `cd Packages/HarnessKit && swift test --filter "HarnessCapabilities|ClaudeLaunch"`
Expected: FAIL — `cannot find 'HarnessCapabilities' in scope`.

- [ ] **Step 3: Implementar `HarnessCapabilities`**

```swift
/// O que um harness sabe fazer.
///
/// Existe para impedir que a abstração vire ficção (spec §10): a UI lê estas
/// bandeiras e esconde o que o harness atual não suporta, em vez de oferecer
/// ações que falham. Todo default é `false` — um harness só ganha um botão
/// depois de declarar que o sustenta.
public struct HarnessCapabilities: Equatable, Sendable {
    /// Encaminha pedidos de permissão ao cliente em vez de decidir sozinho.
    /// Sem isto, não existe diálogo de aprovação: o harness já decidiu.
    public var routesPermissionRequests: Bool
    public var canInterrupt: Bool
    public var canSetPermissionMode: Bool
    public var canSetModelInSession: Bool
    public var canResumeSession: Bool
    public var canForkSession: Bool

    public init(
        routesPermissionRequests: Bool = false,
        canInterrupt: Bool = false,
        canSetPermissionMode: Bool = false,
        canSetModelInSession: Bool = false,
        canResumeSession: Bool = false,
        canForkSession: Bool = false
    ) {
        self.routesPermissionRequests = routesPermissionRequests
        self.canInterrupt = canInterrupt
        self.canSetPermissionMode = canSetPermissionMode
        self.canSetModelInSession = canSetModelInSession
        self.canResumeSession = canResumeSession
        self.canForkSession = canForkSession
    }
}
```

- [ ] **Step 4: Implementar `ClaudeLaunch`**

```swift
import Foundation
import HarnessCore

/// Monta a invocação do Claude Code e declara o que ele suporta.
///
/// Tudo que é específico deste harness mora aqui e em `ClaudeDiscovery`.
public enum ClaudeLaunch {
    public static func make(
        installation: HarnessInstallation,
        workingDirectory: URL,
        sessionID: UUID,
        resuming harnessSessionID: UUID? = nil,
        model: String? = nil,
        permissionMode: String? = nil,
        additionalDirectories: [URL] = []
    ) -> ProcessTransport.Launch {
        var arguments = [
            "-p",
            "--output-format", "stream-json",
            "--input-format", "stream-json",
            "--include-partial-messages",
            "--verbose",
            // A flag que faz o CLI PERGUNTAR em vez de decidir sozinho. Não
            // aparece em `claude --help`; foi encontrada no código do binário
            // 2.1.236 e confirmada no SDK oficial. Sem ela, nenhum
            // control_request de can_use_tool chega — ver
            // docs/superpowers/notes-2026-09-17-protocolo-observado.md
            "--permission-prompt-tool", "stdio",
            "--session-id", sessionID.uuidString.lowercased(),
        ]
        if let harnessSessionID {
            arguments += ["--resume", harnessSessionID.uuidString.lowercased()]
        }
        if let model { arguments += ["--model", model] }
        if let permissionMode { arguments += ["--permission-mode", permissionMode] }
        for directory in additionalDirectories {
            arguments += ["--add-dir", directory.path]
        }

        var environment = ProcessInfo.processInfo.environment
        // O SDK oficial anuncia a si mesmo assim (`sdk-py`, `sdk-ts`). Anunciar
        // o DevSpace mantém a telemetria do harness honesta sobre quem o chamou.
        environment["CLAUDE_CODE_ENTRYPOINT"] = "devspace"

        return ProcessTransport.Launch(
            executable: installation.executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment
        )
    }

    /// O que o Claude Code suporta quando lançado por `make(...)`.
    ///
    /// `routesPermissionRequests` é verdadeiro porque `make` passa
    /// `--permission-prompt-tool stdio`. Se a flag sair dali, esta declaração
    /// vira mentira — as duas coisas andam juntas.
    public static func capabilities(for installation: HarnessInstallation) -> HarnessCapabilities {
        HarnessCapabilities(
            routesPermissionRequests: true,
            canInterrupt: true,
            canSetPermissionMode: true,
            canSetModelInSession: false,
            canResumeSession: true,
            canForkSession: true
        )
    }
}
```

**Sobre `canSetModelInSession: false`:** `set_model` existe no protocolo, mas não foi verificado contra o CLI real. Declarar `false` é a resposta conservadora que a spec §4.1 pede — a UI esconde o botão até alguém confirmar que funciona.

- [ ] **Step 5: Rodar e confirmar que passam**

Run: `cd Packages/HarnessKit && swift test --filter "HarnessCapabilities|ClaudeLaunch"`
Expected: PASS, 10 testes.

- [ ] **Step 6: Rodar a suíte inteira**

Run: `cd Packages/HarnessKit && swift build && swift test`
Expected: build limpo sem warnings; todos os testes verdes. Confirme que o tempo de execução não passou de ~250 ms.

- [ ] **Step 7: Commit**

```bash
git add Packages/HarnessKit
git commit -m "feat(harnesskit): HarnessCapabilities e a invocação do Claude Code

ClaudeLaunch passa --permission-prompt-tool stdio, que é o que faz o CLI pedir
permissão ao cliente em vez de decidir sozinho. A flag não aparece no --help;
foi encontrada no binário e confirmada no SDK oficial.

HarnessCapabilities tem todo default false: um harness só ganha um botão na UI
depois de declarar que o sustenta."
```

---

## Ao fim deste plano

Existe: um canal que separa conversa de controle, correlaciona respostas, entrega pedidos de permissão com as sugestões do próprio harness, e responde por eles; mais a invocação correta do Claude Code e a declaração do que ele suporta. Os tipos genéricos estão em `HarnessCore`, alcançáveis por um segundo adaptador sem importar nada do Claude.

Não existe, por decisão: o mapper de eventos, o modelo `Session`/`Segment`/`TranscriptEntry`, o `TranscriptStore` e a UI. São a Etapa 4 e a 5.

**Verificação que este plano deliberadamente não faz:** nada aqui roda o `claude` real. O fixture `permission-request.ndjson` é a evidência de que o contrato está certo, e ele foi gravado uma vez, com custo conhecido. Um teste de integração opcional pode ser acrescentado depois, atrás de `HARNESSKIT_INTEGRATION`, mas não é pré-requisito para a Etapa 4.
