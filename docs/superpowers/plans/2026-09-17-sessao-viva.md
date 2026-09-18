# Sessão Viva Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Costurar o transporte, o canal de controle, o mapeador e o store numa
sessão viva: subir o harness, mandar turnos, resolver permissões, interromper,
parar — e gravar o transcript enquanto isso acontece.

**Architecture:** `ClaudeSession` é o único componente que enxerga os dois
fluxos no instante em que nascem, então é ele quem grava. O efêmero sai pelo
`events`; o durável vai direto ao store. Nada acima precisa reconciliar os
dois, porque eles nunca se separam.

**Tech Stack:** Swift 6, Swift Testing, zero dependências. O teste de ponta a
ponta sobe um harness FALSO — um shell script que reproduz uma fixture
gravada — então o caminho inteiro é exercitado sem gastar um centavo.

**Spec:** `docs/superpowers/specs/2026-09-16-devspace-fundacao-design.md`
(§4.1 abstração de harness, §4.2 modelo de domínio, §4.3 persistência,
§4.4 camadas, §5.1 quente/fria, §5.3 taxonomia de erro, §5.4 tolerância,
§5.5 interrupção, §5.6 permissão pendente, §7.1 estrutura)

**Pendências que este plano fecha:** `docs/superpowers/notes-2026-09-17-pendencias.md`
— o seam de permissão, o nome da ferramenta em streaming, e o buraco de
tolerância no interior dos casos conhecidos.

**Contrato de fio observado:** `docs/superpowers/notes-2026-09-17-protocolo-observado.md`

## Global Constraints

- `swift-tools-version:6.0`; plataforma `.macOS(.v15)`; concorrência estrita do Swift 6.
- **Zero dependências externas** em `Package.swift`.
- Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`) — nunca XCTest.
- **Nenhum teste executa o `claude`.** Nem uma vez, nem "para conferir". As fixtures
  custaram dinheiro real e `harness-probe record` se recusa a sobrescrever.
- As fixtures em `Tests/ClaudeHarnessTests/Fixtures/` são **estritamente de leitura**.
- **Sem asserções de tempo de relógio.** Todo prazo é injetável; um teste afere que a
  escalada ACONTECEU, nunca quanto tempo levou.
- **Spec §7.1:** nada em `Sources/HarnessCore` pode conter as palavras `claude`,
  `codex`, `opencode` — nem em código, nem em comentário, nem em string.
  `harnessCoreNeverNamesASpecificHarness` varre a prosa.
- **Spec §4.2:** o transcript é um registro semântico FIEL, não um log de exibição.
- **Spec §5.4:** conteúdo desconhecido é preservado, nunca descartado nem propagado
  como erro — e reencode de um caso degradado reemite o original, nunca a palavra
  "unrecognized".
- Comentários e documentação em português.

---

## Decisões fixadas (não reabrir durante a execução)

### D1 — A sessão escreve no store

A alternativa seria uma camada acima consumir `events` e gravar. Isso obrigaria
as entradas duráveis a viajarem dentro de `SessionEvent` — exatamente o
acoplamento que a Etapa 4b separou, e que a spec §4.4 existe para impedir.

`ClaudeSession` é o único componente que enxerga `MappedOutput.events` e
`MappedOutput.entries` no mesmo instante, saídos da mesma linha. É o único
lugar onde os dois não podem divergir.

### D2 — O usage autoritativo é o da linha `result`

Por turno, somado em `Segment.usage`, persistido com `saveMetadata`.

**Nunca some o usage das linhas `assistant`.** O review final mediu: este CLI
emite uma linha `assistant` por bloco de conteúdo, e linhas que compartilham
`message.id` repetem o mesmo `message.usage` verbatim. Em
`permission-denied.ndjson` são 12 linhas para 7 ids distintos — somar por linha
dá 162.264 tokens de cache lido contra os 93.511 reais que a linha `result`
reporta. O doc comment de `ClaudeEventMapper.assistant(_:)` já registra a
medição.

### D3 — O seam de permissão carrega o `raw`

Pendência registrada: `ControlChannel.consume` tem a linha crua na mão e
entrega `.permissionRequest(request)` sem ela, então
`ClaudeEventMapper.entry(for:raw:)` não tem chamador que possa alimentá-lo.
Consequência hoje: um pedido de permissão não é duplicado — é **perdido**.

A Task 1 fecha isso carregando `raw` no caso do `ChannelOutput`, não em
`PermissionRequest`: o tipo neutro é o que a UI consome, e a UI não tem o que
fazer com o payload de fio.

### D4 — `PermissionDecision` ganha decode tolerante ANTES de ganhar `.expired`

A spec §5.6 exige registrar uma permissão pendente no fechamento como
`.expired`. Acrescentar um caso a um enum `Codable` sintetizado e fechado é
**precisamente** o buraco que a pendência previu: um binário mais velho lê a
entrada, reconhece o discriminador `permissionDecision`, entra no decode
sintetizado, e estoura — descartando a entrada inteira, `raw` e tudo.

Por isso a ordem é obrigatória: Task 2 torna o decode tolerante primeiro
(terceira aplicação do mesmo padrão de `TranscriptEntry.Kind` e `Handoff`),
e só então acrescenta o caso.

### D5 — `blockStarted` entra agora, e isto reverte um adiamento anterior

A revisão final da Etapa 4b apontou que `content_block_start` é o ÚNICO quadro
que carrega o nome da ferramenta durante o streaming, e ele era descartado.
Eu adiei, argumentando que a forma do evento deveria ser puxada pelo cockpit.

Reverto por duas razões. Primeira: este é o plano que produz o `events` de
verdade, com um contrato que alguém vai implementar contra — se a forma vai ser
decidida, é aqui. Segunda: a forma não é ambígua. O quadro traz índice, tipo do
bloco e, quando é ferramenta, id e nome; não há o que inventar. E o custo de
adiar cresce: cada golden novo que depende das contagens de evento encarece a
mudança.

### D6 — A interrupção tem dois prazos, e um deles já existe

`ProcessTransport.terminate()` **já** faz SIGTERM → espera → SIGKILL com os
orçamentos da §5.5, injetáveis desde a Etapa 1. O que falta é o prazo de
protocolo: `interrupt()` corre `channel.send(.interrupt)` contra um deadline
de 5 s; se estourar, chama `stop()`, que cai no `terminate()` que já existe.

Não reimplemente a escalada de sinal.

### D7 — O teste de ponta a ponta sobe um harness falso

Um shell script que escreve num stdout as linhas de uma fixture gravada, e —
para o caminho de permissão — lê uma linha do stdin antes de continuar.

Isso exercita `Process` de verdade, pipes de verdade, o enquadramento NDJSON de
verdade, o canal de controle de verdade e o mapeador de verdade. O único
componente falso é o programa do outro lado do pipe. Custo: zero.

### D8 — Duas divergências deliberadas da assinatura esboçada na §4.1

1. **`SessionSpec` carrega três ids, não um.** A §4.1 escreve `sessionID:
   UUID // gerado por nós, vira --session-id`. Mas o modelo da §4.2 tem três
   identidades distintas: `Session.id` (a conversa), `Segment.id` (o trecho) e
   `Segment.harnessSessionID` (o `--session-id`). Uma sessão viva precisa das
   três para saber onde gravar.
2. **`events` é `AsyncThrowingStream`, não `AsyncStream`.** Uma sessão que
   morre precisa contar isso a quem a consome; um fluxo não-lançável só sabe
   acabar em silêncio, e "acabou" e "quebrou" são dois estados de UI muito
   diferentes. Mesma licença que `TranscriptStore` já tomou duas vezes: a §4.3
   e a §4.1 são esboços de assinatura, e o comportamento errado que a
   literalidade deixaria passar custa mais que a fidelidade.

---

## File Structure

**Criar:**

| Arquivo | Responsabilidade |
|---|---|
| `Sources/HarnessCore/Harness.swift` | Os protocolos `Harness` e `HarnessSession` (§4.1), neutros |
| `Sources/HarnessCore/SessionSpec.swift` | `SessionSpec`, `UserTurn` |
| `Sources/HarnessCore/HarnessError.swift` | A taxonomia da §5.3 |
| `Sources/ClaudeHarness/ClaudeSession.swift` | A sessão viva |
| `Sources/ClaudeHarness/ClaudeHarnessAdapter.swift` | `Harness` para este CLI |
| `Sources/HarnessTestSupport/FakeHarnessScript.swift` | O harness falso do D7 (é alvo de *fonte*, não de teste) |
| `Tests/HarnessCoreTests/HarnessContractTests.swift` | Os contratos, contra um duplo |
| `Tests/ClaudeHarnessTests/ClaudeSessionTests.swift` | A sessão, por unidade |
| `Tests/ClaudeHarnessTests/ClaudeSessionEndToEndTests.swift` | O caminho inteiro |

**Modificar:**

| Arquivo | Mudança |
|---|---|
| `Sources/ClaudeHarness/ControlFrames.swift` | `ControlFrame.permissionRequest` carrega `raw` |
| `Sources/ClaudeHarness/ControlChannel.swift` | `ChannelOutput.permissionRequest` carrega `raw` |
| `Sources/HarnessCore/Permission.swift` | `PermissionDecision`: decode tolerante + `.expired` |
| `Sources/HarnessCore/SessionEvent.swift` | `.blockStarted` |
| `Sources/ClaudeHarness/ClaudeEventMapper.swift` | Mapeia `content_block_start` |
| `Sources/harness-probe/main.swift` | Consumidor de `ChannelOutput.permissionRequest` |

**Não mexer:** `Package.swift` (todos os alvos e dependências de que este plano
precisa já existem), `ProcessTransport.swift`, `FileTranscriptStore.swift`,
`TranscriptEntry.swift`, `Session.swift`, as fixtures.

---

### Task 1: O seam de permissão carrega o `raw`

**Files:**
- Modify: `Packages/HarnessKit/Sources/ClaudeHarness/ControlFrames.swift` (linhas 9 e 53)
- Modify: `Packages/HarnessKit/Sources/ClaudeHarness/ControlChannel.swift` (linhas 9, 147, 153)
- Modify: `Packages/HarnessKit/Sources/harness-probe/main.swift` (linha 466)
- Modify: `Packages/HarnessKit/Tests/ClaudeHarnessTests/ControlFramesTests.swift`
- Modify: `Packages/HarnessKit/Tests/ClaudeHarnessTests/ControlChannelTests.swift`
- Modify: `Packages/HarnessKit/Tests/ClaudeHarnessTests/PermissionRoundTripTests.swift` (4 sítios)

**Interfaces:**
- Produces: `ControlFrame.permissionRequest(PermissionRequest, raw: JSONValue)` e
  `ChannelOutput.permissionRequest(PermissionRequest, raw: JSONValue)`.
  A Task 7 consome o `raw` para cunhar a entrada do transcript.

**Por que o `raw` vai no caso e não em `PermissionRequest`.** O tipo neutro é o
que a UI consome para montar o diálogo; o payload de fio não tem uso nenhum
lá, e pô-lo dentro obrigaria todo adaptador futuro a carregá-lo mesmo quando o
protocolo dele não tem um envelope equivalente. O caso do canal é o lugar onde
a linha crua de fato existe.

**Nada disto é opcional para compilar.** Acrescentar um segundo valor associado
quebra todo `case .permissionRequest(let request)` existente — o compilador
lista os sítios para você. Não os silencie com `_` sem olhar: `PermissionRoundTripTests`
e o `harness-probe` são consumidores reais.

**NÃO execute o `harness-probe`.** Edite-o e compile-o; executá-lo gasta crédito
de API de verdade.

- [ ] **Step 1: Escrever o teste que falha**

Acrescentar ao final de `Tests/ClaudeHarnessTests/ControlFramesTests.swift`:

```swift
/// Pendência do fim da Etapa 4b: o canal tinha a linha na mão e a jogava fora,
/// então `ClaudeEventMapper.entry(for:raw:)` não tinha chamador que pudesse
/// alimentá-lo — e o pedido de permissão não era duplicado, era perdido.
@Test func aPermissionRequestCarriesTheFrameItCameFrom() throws {
    let line = Data(#"""
    {"type":"control_request","request_id":"req-7","request":{"subtype":"can_use_tool",
     "tool_name":"Write","input":{"file_path":"/tmp/a.txt"},"tool_use_id":"toolu_9"}}
    """#.utf8)
    guard case .permissionRequest(let request, let raw) = ControlFrame.classify(line) else {
        Issue.record("esperava .permissionRequest"); return
    }
    #expect(request.id == "req-7")
    #expect(request.toolName == "Write")
    // O envelope INTEIRO, não só o corpo do request: é o que a spec §4.2
    // chama de registro fiel.
    #expect(raw["type"]?.stringValue == "control_request")
    #expect(raw["request"]?["tool_use_id"]?.stringValue == "toolu_9")
}
```

E ao final de `Tests/ClaudeHarnessTests/PermissionRoundTripTests.swift`:

```swift
/// O mesmo `raw`, agora atravessando o canal até o consumidor.
@Test func theChannelHandsTheRawFrameToTheConsumer() async throws {
    let harness = FakeHarnessScript.permissionRequest()
    defer { harness.cleanUp() }

    let channel = ControlChannel(transport: ProcessTransport())
    let stream = try await channel.start(harness.launch)
    defer { Task { await channel.stop() } }

    for try await output in stream {
        guard case .permissionRequest(let request, let raw) = output else { continue }
        #expect(raw["request_id"]?.stringValue == request.id)
        #expect(raw["type"]?.stringValue == "control_request")
        return
    }
    Issue.record("o fluxo acabou sem entregar um pedido de permissão")
}
```

> Este segundo teste depende de `FakeHarnessScript`, que nasce na Task 3. Se
> você está na Task 1, escreva só o primeiro teste e deixe o segundo para a
> Task 3 — anote isso no seu relatório.

- [ ] **Step 2: Rodar e verificar que falha**

```bash
cd Packages/HarnessKit && swift test --filter ControlFrames
```
Esperado: FALHA de compilação — `.permissionRequest` tem um valor associado, não dois.

- [ ] **Step 3: Acrescentar o `raw` aos dois enums**

Em `ControlFrames.swift`, o caso na linha 9:

```swift
    /// O harness está pedindo permissão para usar uma ferramenta.
    ///
    /// Carrega o quadro inteiro junto: é a única cópia da linha de fio que
    /// existe, e o transcript precisa dela para ser o registro fiel que a
    /// spec §4.2 exige. `PermissionRequest` fica neutro — a UI monta o
    /// diálogo a partir dele e não tem o que fazer com o envelope.
    case permissionRequest(PermissionRequest, raw: JSONValue)
```

E o retorno na linha 53: `return .permissionRequest(parsed, raw: value)`.

Em `ControlChannel.swift`, o caso na linha 9 ganha a mesma forma e a mesma
doc; o `switch` em 147 vira `case .permissionRequest(let request, let raw):`
e o retorno em 153, `return .permissionRequest(request, raw: raw)`.

- [ ] **Step 4: Corrigir os consumidores que o compilador apontar**

`harness-probe/main.swift:466` e os quatro sítios de
`PermissionRoundTripTests.swift`, mais o que mais aparecer. Onde o `raw` não
interessa ao sítio, `case .permissionRequest(let request, _):` é a forma
correta — mas olhe cada um antes de descartar.

- [ ] **Step 5: Rodar a suíte inteira**

```bash
cd Packages/HarnessKit && swift build && swift test
```
Esperado: build limpo, tudo verde. As contagens das quatro fixtures do mapeador
não podem mudar — esta task não toca no mapeador.

- [ ] **Step 6: Commit**

```bash
git add Packages/HarnessKit/Sources/ClaudeHarness/ControlFrames.swift \
        Packages/HarnessKit/Sources/ClaudeHarness/ControlChannel.swift \
        Packages/HarnessKit/Sources/harness-probe/main.swift \
        Packages/HarnessKit/Tests/ClaudeHarnessTests/
git commit -m "fix(claude): o pedido de permissão carrega o quadro de onde veio"
```

---

### Task 2: `PermissionDecision` tolerante, e só então `.expired`

**Files:**
- Modify: `Packages/HarnessKit/Sources/HarnessCore/Permission.swift`
- Test: `Packages/HarnessKit/Tests/HarnessCoreTests/PermissionDecisionToleranceTests.swift` (criar)

**Interfaces:**
- Produces: `PermissionDecision.expired` e um decode que degrada em vez de estourar.
  A Task 7 grava `.expired` no fechamento (spec §5.6).

**A ordem desta task é obrigatória, e esta é a razão.** A pendência registrada
ao fim da Etapa 4a dizia: a degradação chegou à camada do DISCRIMINADOR e
parou; o interior de um caso conhecido ainda é `Codable` sintetizado sobre
tipos fechados. E nomeava o contraexemplo exato — a spec §5.6 já agenda um
`PermissionDecision.expired`; quando ele existir, o leitor de hoje reconhece
`permissionDecision`, entra no decode sintetizado, e estoura. Medido na época:
3 linhas gravadas, 2 lidas.

Esta é a terceira aplicação do mesmo padrão, depois de `TranscriptEntry.Kind`
e `Handoff`. Siga a forma que já existe nos dois — espelho `Known`,
`knownDiscriminators` DERIVADO de `Known.CodingKeys`, e reencode idempotente
que reemite o discriminador original.

- [ ] **Step 1: Escrever o teste que falha**

Em `Tests/HarnessCoreTests/PermissionDecisionToleranceTests.swift`:

```swift
import Testing
import Foundation
@testable import HarnessCore

private let encoder = JSONEncoder()
private let decoder = JSONDecoder()

@Test func theTwoKnownDecisionsRoundTrip() throws {
    for decision: PermissionDecision in [
        .allow(updatedInput: nil),
        .allow(updatedInput: .object(["command": .string("ls")])),
        .deny(message: "não", interrupt: false),
        .deny(message: "pare", interrupt: true),
    ] {
        let data = try encoder.encode(decision)
        #expect(try decoder.decode(PermissionDecision.self, from: data) == decision)
    }
}

@Test func theExpiredDecisionRoundTrips() throws {
    let data = try encoder.encode(PermissionDecision.expired)
    #expect(try decoder.decode(PermissionDecision.self, from: data) == .expired)
}

/// O cenário que a pendência da Etapa 4a nomeou: uma versão futura grava um
/// quarto caso, e este binário o abre sem perder a entrada.
@Test func anUnknownDecisionDegradesInsteadOfFailingTheDecode() throws {
    let future = Data(#"{"escalated":{"_0":"para o time de segurança"}}"#.utf8)
    let decoded = try decoder.decode(PermissionDecision.self, from: future)
    guard case .unrecognized(let discriminator, let payload) = decoded else {
        Issue.record("esperava .unrecognized, veio \(decoded)"); return
    }
    #expect(discriminator == "escalated")
    #expect(payload["_0"]?.stringValue == "para o time de segurança")
}

/// Idempotência: um binário velho que abre e REGRAVA não pode degradar o
/// registro permanentemente — inclusive para a versão nova, que entende o
/// caso que ela mesma escreveu.
@Test func decodingAnUnknownDecisionAndReencodingItIsIdempotent() throws {
    let future = Data(#"{"escalated":{"_0":"para o time de segurança"}}"#.utf8)
    let reencoded = try encoder.encode(decoder.decode(PermissionDecision.self, from: future))
    let asValue = try decoder.decode(JSONValue.self, from: reencoded)
    #expect(asValue.objectValue?.keys.first == "escalated")
    #expect(asValue["escalated"]?["_0"]?.stringValue == "para o time de segurança")
}

/// JSON genuinamente corrompido continua estourando — só o caso "objeto de uma
/// chave só cujo discriminador não conhecemos" degrada.
@Test func genuinelyCorruptJSONStillThrows() {
    #expect(throws: (any Error).self) {
        try decoder.decode(PermissionDecision.self, from: Data(#"{"a":1,"b":2}"#.utf8))
    }
    #expect(throws: (any Error).self) {
        try decoder.decode(PermissionDecision.self, from: Data(#""allow""#.utf8))
    }
}

/// O terceiro elo da cadeia que o compilador NÃO impõe, pela mesma razão
/// documentada em `TranscriptEntry.Kind.knownDiscriminators`.
@Test func theDecisionKnownDiscriminatorsDoNotDiverge() throws {
    for decision: PermissionDecision in [
        .allow(updatedInput: nil), .deny(message: "x", interrupt: false), .expired,
    ] {
        let data = try encoder.encode(decision)
        let key = try #require(decoder.decode(JSONValue.self, from: data).objectValue?.keys.first)
        #expect(PermissionDecision.knownDiscriminators.contains(key),
                "o caso \(decision) encoda como \"\(key)\", que não está em knownDiscriminators")
    }
}
```

- [ ] **Step 2: Rodar e verificar que falha**

```bash
cd Packages/HarnessKit && swift test --filter PermissionDecisionTolerance
```
Esperado: FALHA de compilação — `.expired` e `.unrecognized` não existem.

- [ ] **Step 3: Reescrever `PermissionDecision` em `Permission.swift`**

Substituir o enum inteiro (mantendo a doc que já está lá acima dele, sobre a
§7.1, e acrescentando a nova):

```swift
public enum PermissionDecision: Equatable, Sendable, Codable {
    case allow(updatedInput: JSONValue?)
    case deny(message: String, interrupt: Bool)
    /// A decisão que ninguém tomou: a sessão fechou com o pedido em aberto
    /// (spec §5.6). Na retomada o harness pergunta de novo.
    ///
    /// Registrar isso como `.deny` seria mentir sobre o que aconteceu — o
    /// usuário não negou nada —, e omiti-lo deixaria no transcript um
    /// `.permissionRequest` sem resposta, que um replay lê como uma pergunta
    /// que ficou pendurada para sempre.
    case expired
    /// Uma decisão que esta versão não conhece, preservada em vez de perdida.
    case unrecognized(discriminator: String, payload: JSONValue)

    /// Espelho dos casos conhecidos, com o mesmo formato de fio que
    /// `PermissionDecision` teria se sua `Codable` fosse inteiramente
    /// sintetizada. Ver a nota equivalente em `TranscriptEntry.Kind.Known`.
    private enum Known: Equatable, Sendable, Codable {
        case allow(updatedInput: JSONValue?)
        case deny(message: String, interrupt: Bool)
        case expired

        /// Escrita à mão, idêntica à sintetizada, só para que
        /// `knownDiscriminators` seja derivado dela.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case allow, deny, expired
        }
    }

    static let knownDiscriminators: Set<String> =
        Set(Known.CodingKeys.allCases.map(\.stringValue))

    public init(from decoder: Decoder) throws {
        let peek = try decoder.container(keyedBy: DiscriminatorKey.self)
        guard peek.allKeys.count == 1, let key = peek.allKeys.first else {
            throw DecodingError.dataCorruptedError(
                forKey: DiscriminatorKey(stringValue: "decision")!,
                in: peek,
                debugDescription: "PermissionDecision espera exatamente uma chave discriminadora, achou \(peek.allKeys.count)"
            )
        }
        guard PermissionDecision.knownDiscriminators.contains(key.stringValue) else {
            let payload = try peek.decode(JSONValue.self, forKey: key)
            self = .unrecognized(discriminator: key.stringValue, payload: payload)
            return
        }
        switch try Known(from: decoder) {
        case .allow(let updatedInput): self = .allow(updatedInput: updatedInput)
        case .deny(let message, let interrupt): self = .deny(message: message, interrupt: interrupt)
        case .expired: self = .expired
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .allow(let updatedInput): try Known.allow(updatedInput: updatedInput).encode(to: encoder)
        case .deny(let message, let interrupt):
            try Known.deny(message: message, interrupt: interrupt).encode(to: encoder)
        case .expired: try Known.expired.encode(to: encoder)
        case .unrecognized(let discriminator, let payload):
            // Reemite o discriminador e o payload ORIGINAIS — ver a exigência
            // de idempotência em `TranscriptEntry.Kind`.
            var container = encoder.container(keyedBy: DiscriminatorKey.self)
            try container.encode(payload, forKey: DiscriminatorKey(stringValue: discriminator)!)
        }
    }
}
```

Acrescente acima do tipo, junto da doc que já existe, uma nota curta dizendo
que o decode é tolerante pelo mesmo motivo e com a mesma mecânica de
`TranscriptEntry.Kind`, e que esta foi a pendência aberta ao fim da Etapa 4a.

- [ ] **Step 4: Corrigir o que o compilador apontar**

`PermissionDecision.responseData(requestID:)` em `ControlFrames.swift` faz
`switch` exaustivo e vai quebrar. `.expired` e `.unrecognized` **não são
respondíveis ao harness** — não existe comportamento de fio para "expirou".
Faça o método lançar em vez de inventar uma resposta:

```swift
    /// - Throws: para `.expired` e `.unrecognized`, que não têm forma de fio.
    ///   `.expired` descreve uma sessão que FECHOU com o pedido em aberto —
    ///   não há para quem responder. Devolver "deny" no lugar diria ao harness
    ///   que o usuário negou, que é uma coisa diferente e falsa.
```

Escolha o erro: um caso novo em `ControlChannel.ChannelError` (`.undeliverableDecision`)
é a forma que combina com o resto do arquivo. Acrescente um teste para ele.

- [ ] **Step 5: Rodar**

```bash
cd Packages/HarnessKit && swift build && swift test
```
Esperado: build limpo, tudo verde.

- [ ] **Step 6: Commit**

```bash
git add Packages/HarnessKit/Sources/HarnessCore/Permission.swift \
        Packages/HarnessKit/Sources/ClaudeHarness/ControlFrames.swift \
        Packages/HarnessKit/Tests/
git commit -m "feat(core): PermissionDecision degrada em vez de estourar, e ganha .expired"
```

---

### Task 3: O efêmero aprende a nomear a ferramenta em streaming

**Files:**
- Modify: `Packages/HarnessKit/Sources/HarnessCore/SessionEvent.swift`
- Modify: `Packages/HarnessKit/Sources/ClaudeHarness/ClaudeEventMapper.swift` (`ephemeral(_:)`)
- Modify: `Packages/HarnessKit/Tests/ClaudeHarnessTests/ClaudeEventMapperTests.swift`
- Modify: `Packages/HarnessKit/Tests/ClaudeHarnessTests/ClaudeEventMapperFixtureTests.swift` (só as contagens de EVENTO)

**Interfaces:**
- Produces: `SessionEvent.blockStarted(blockIndex: Int, block: StreamedBlock)` e
  `enum StreamedBlock { case text, thinking, toolUse(id: String, name: String) }`.

**O buraco que isto fecha.** `content_block_start` era descartado, e ele é o
ÚNICO quadro que carrega o nome da ferramenta durante o streaming. Um cockpit
que recebe `toolInputDelta(blockIndex: 0, partialJSON: "{\"comm")` não consegue
dizer QUAL ferramenta está sendo montada; o nome só chega quando a linha
`assistant` fecha o bloco. Em `permission-denied.ndjson` são 63
`input_json_delta` — uma espera longa mostrando "montando a chamada…" sem
dizer do quê.

**As contagens de evento das fixtures MUDAM, e é a única coisa que muda.**
As contagens de ENTRADA não podem se mover — se alguma se mover, pare e
reporte, porque significa que esta task mexeu no durável. Os novos números,
medidos: `hello` 5 → **6**, `tool-use` 42 → **44**, `permission-denied`
220 → **232**, `permission-request` 1 → **1** (esta fixture não tem streaming).
Recalcule e confira antes de aceitar; se divergir do que está escrito aqui,
reporte a divergência em vez de ajustar.

- [ ] **Step 1: Escrever o teste que falha**

Acrescentar a `ClaudeEventMapperTests.swift`:

```swift
@Test func aStreamingToolCallAnnouncesItsNameWhenTheBlockOpens() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"stream_event","event":{"type":"content_block_start","index":0,
     "content_block":{"type":"tool_use","id":"toolu_1","name":"Bash","input":{},
                      "caller":{"type":"direct"}}}}
    """#))
    #expect(out.events == [.blockStarted(blockIndex: 0,
                                         block: .toolUse(id: "toolu_1", name: "Bash"))])
    #expect(out.entries.isEmpty)
}

@Test func aTextBlockAnnouncesItselfToo() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"stream_event","event":{"type":"content_block_start","index":1,
     "content_block":{"type":"text","text":""}}}
    """#))
    #expect(out.events == [.blockStarted(blockIndex: 1, block: .text)])
}

@Test func aThinkingBlockAnnouncesItself() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"stream_event","event":{"type":"content_block_start","index":2,
     "content_block":{"type":"thinking","thinking":""}}}
    """#))
    #expect(out.events == [.blockStarted(blockIndex: 2, block: .thinking)])
}

/// Degradar, não adivinhar: um `tool_use` sem nome não vira `.toolUse(name: "")`
/// — a UI mostraria uma ferramenta chamada nada. E, acima de tudo, um
/// `content_block_start` de qualquer forma continua sem produzir entrada
/// durável (D1).
@Test func aMalformedBlockStartProducesNoEventAndNoEntry() throws {
    for line in [
        #"{"type":"stream_event","event":{"type":"content_block_start","index":0}}"#,
        #"{"type":"stream_event","event":{"type":"content_block_start","content_block":{"type":"text"}}}"#,
        #"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t"}}}"#,
        #"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"bloco_novo"}}}"#,
    ] {
        let out = try makeMapper().map(json(line))
        #expect(out == .empty, "linha: \(line)")
    }
}
```

E, em `ClaudeEventMapperFixtureTests.swift`, atualizar SÓ a segunda coluna
numérica da tabela de argumentos e as duas asserções de contagem de evento em
`theDeltaStreamNeverReachesTheTranscript`. **Não toque nas contagens de entrada
nem na lista ordenada de 27 tipos.**

- [ ] **Step 2: Rodar e verificar que falha**

```bash
cd Packages/HarnessKit && swift test --filter ClaudeEventMapper
```
Esperado: FALHA de compilação (`blockStarted` não existe) e, depois de ela
compilar, as fixtures falhando pelas contagens antigas.

- [ ] **Step 3: Acrescentar o caso em `SessionEvent.swift`**

```swift
    /// Um bloco de conteúdo abriu no turno corrente.
    ///
    /// É o único lugar do fluxo que sabe o NOME da ferramenta enquanto a
    /// chamada ainda está sendo montada: os deltas seguintes só trazem
    /// fragmentos de JSON, e o nome só reaparece quando o turno consolida.
    /// Sem isto, a UI passa dezenas de deltas mostrando "montando a chamada…"
    /// sem dizer do quê.
    case blockStarted(blockIndex: Int, block: StreamedBlock)
```

E, no mesmo arquivo, fora do enum:

```swift
/// O que um bloco de conteúdo é, no instante em que abre.
///
/// Conjunto fechado e pequeno de propósito: é vocabulário de EXIBIÇÃO, e um
/// tipo de bloco que este harness não conhece simplesmente não abre evento —
/// o conteúdo dele chega consolidado no transcript de qualquer forma, que é
/// onde a fidelidade da spec §4.2 é cobrada. Degradar aqui seria pedir à UI
/// que renderizasse um nome que ela não sabe desenhar.
public enum StreamedBlock: Sendable, Equatable {
    case text
    case thinking
    case toolUse(id: String, name: String)
}
```

- [ ] **Step 4: Mapear `content_block_start` em `ephemeral(_:)`**

O `switch` de `ephemeral(_:)` ganha um caso antes do `default`:

```swift
        case "content_block_start":
            return MappedOutput(events: blockStart(event).map { [$0] } ?? [])
```

E, junto de `delta(_:)`:

```swift
    /// O nome da ferramenta, no único quadro que o carrega durante o streaming.
    ///
    /// Devolve `nil` — e portanto evento nenhum — para um bloco malformado ou
    /// de um tipo que não conhecemos. Isso não perde nada: o bloco inteiro
    /// chega consolidado na linha `assistant` e vira entrada durável lá.
    private func blockStart(_ event: JSONValue) -> SessionEvent? {
        guard let index = event["index"]?.intValue,
              let block = event["content_block"],
              let kind = block["type"]?.stringValue
        else { return nil }

        switch kind {
        case "text": return .blockStarted(blockIndex: index, block: .text)
        case "thinking": return .blockStarted(blockIndex: index, block: .thinking)
        case "tool_use":
            // Sem nome não há o que anunciar: `.toolUse(name: "")` poria na
            // tela uma ferramenta chamada nada.
            guard let id = block["id"]?.stringValue,
                  let name = block["name"]?.stringValue else { return nil }
            return .blockStarted(blockIndex: index, block: .toolUse(id: id, name: name))
        default:
            return nil
        }
    }
```

Atualize o comentário do `default` de `ephemeral(_:)`, que hoje diz que
`content_block_start` é moldura descartada — deixou de ser.

- [ ] **Step 5: Rodar e conferir as contagens**

```bash
cd Packages/HarnessKit && swift test --filter ClaudeEventMapper
```
Esperado: PASSA. Se uma contagem de ENTRADA se moveu, pare e reporte.

- [ ] **Step 6: Commit**

```bash
git add Packages/HarnessKit/Sources/HarnessCore/SessionEvent.swift \
        Packages/HarnessKit/Sources/ClaudeHarness/ClaudeEventMapper.swift \
        Packages/HarnessKit/Tests/ClaudeHarnessTests/
git commit -m "feat: o fluxo efêmero anuncia o bloco que abre, com o nome da ferramenta"
```

---

### Task 4: Um harness falso, para exercitar o caminho inteiro sem gastar nada

**Files:**
- Create: `Packages/HarnessKit/Sources/HarnessTestSupport/FakeHarnessScript.swift`
- Test: `Packages/HarnessKit/Tests/HarnessCoreTests/FakeHarnessScriptTests.swift`

**Interfaces:**
- Produces:
  - `FakeHarnessScript.replaying(_ ndjson: String) -> FakeHarnessScript`
  - `FakeHarnessScript.permissionRequest() -> FakeHarnessScript`
  - `FakeHarnessScript.hanging() -> FakeHarnessScript`
  - `var launch: ProcessTransport.Launch { get }`
  - `func cleanUp()`

  As Tasks 6-10 sobem sessões com isto.

**Por que um script e não um duplo em memória.** Um duplo trocaria `Process`,
pipes, enquadramento NDJSON e o canal de controle inteiro por uma mentira — e
são exatamente essas camadas que a sessão está costurando. O que este tipo
falsifica é só o programa do outro lado do pipe. Tudo entre ele e o teste é o
código de produção de verdade.

**`/bin/sh` está sempre lá.** Não dependa de `bash`, `python` ou de nada
instalado; o script é POSIX sh puro.

- [ ] **Step 1: Escrever o teste que falha**

Em `Tests/HarnessCoreTests/FakeHarnessScriptTests.swift`:

```swift
import Testing
import Foundation
@testable import HarnessCore
import HarnessTestSupport

@Test func aReplayingHarnessWritesTheLinesItWasGiven() async throws {
    let harness = FakeHarnessScript.replaying(#"""
    {"type":"system","subtype":"init","model":"m","session_id":"s"}
    {"type":"result","is_error":false}
    """#)
    defer { harness.cleanUp() }

    let transport = ProcessTransport()
    var lines: [String] = []
    for try await line in try await transport.start(harness.launch) {
        lines.append(String(decoding: line, as: UTF8.self))
    }
    #expect(lines.count == 2)
    #expect(lines[0].contains(#""subtype":"init""#))
    #expect(lines[1].contains(#""type":"result""#))
}

/// O caminho que importa: o script ESPERA uma resposta no stdin antes de
/// seguir. É isso que torna o pedido de permissão exercitável de ponta a ponta.
@Test func aPermissionHarnessWaitsForTheAnswerBeforeFinishing() async throws {
    let harness = FakeHarnessScript.permissionRequest()
    defer { harness.cleanUp() }

    let transport = ProcessTransport()
    let stream = try await transport.start(harness.launch)
    var iterator = stream.makeAsyncIterator()

    let first = try #require(try await iterator.next())
    #expect(String(decoding: first, as: UTF8.self).contains("control_request"))

    try await transport.write(Data(#"{"type":"control_response"}"#.utf8) + Data("\n".utf8))

    let second = try #require(try await iterator.next())
    #expect(String(decoding: second, as: UTF8.self).contains(#""type":"result""#))
    await transport.terminate()
}

/// O script que nunca responde, para o prazo da interrupção (spec §5.5).
@Test func aHangingHarnessStaysAliveUntilTerminated() async throws {
    let harness = FakeHarnessScript.hanging()
    defer { harness.cleanUp() }

    let transport = ProcessTransport(terminationGracePeriod: .milliseconds(200),
                                     killGracePeriod: .milliseconds(200))
    _ = try await transport.start(harness.launch)
    await transport.terminate()
    // Não aferimos QUANTO tempo levou — só que o processo não está mais lá.
    #expect(await transport.exitCode != nil)
}

@Test func cleanUpRemovesTheScriptFromDisk() throws {
    let harness = FakeHarnessScript.replaying("{}")
    let path = harness.launch.arguments.last ?? ""
    #expect(FileManager.default.fileExists(atPath: path))
    harness.cleanUp()
    #expect(!FileManager.default.fileExists(atPath: path))
}
```

> `transport.exitCode` é uma propriedade de ator existente em
> `ProcessTransport`. Se a grafia não bater, leia o tipo e ajuste a asserção —
> não mude `ProcessTransport`.

- [ ] **Step 2: Rodar e verificar que falha**

```bash
cd Packages/HarnessKit && swift test --filter FakeHarnessScript
```
Esperado: FALHA de compilação — `cannot find 'FakeHarnessScript' in scope`.

- [ ] **Step 3: Escrever `FakeHarnessScript.swift`**

```swift
import Foundation

/// Um harness de mentira: um script de shell que escreve linhas conhecidas no
/// stdout e, quando preciso, espera uma resposta no stdin.
///
/// Existe para que o caminho inteiro — `Process`, pipes, enquadramento NDJSON,
/// canal de controle, mapeador, store — seja exercitado com o código de
/// produção de verdade. O único componente falso é o programa do outro lado do
/// pipe. **Nenhum teste deste pacote executa o harness de verdade**: gravar as
/// fixtures custou crédito de API, e um teste que sobe o CLI real gasta mais a
/// cada execução.
///
/// POSIX sh puro de propósito: `bash`, `python` e afins podem não estar lá; o
/// `/bin/sh` está.
public struct FakeHarnessScript: Sendable {
    public let launch: ProcessTransport.Launch
    private let scriptURL: URL

    private init(body: String) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fake-harness-\(UUID().uuidString).sh")
        try? body.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: url.path)
        self.scriptURL = url
        self.launch = ProcessTransport.Launch(
            executable: "/bin/sh",
            arguments: [url.path],
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
        )
    }

    /// Escreve as linhas dadas, uma por linha, e sai.
    ///
    /// Cada linha vai por um `printf` próprio com `%s\n`, e não por um
    /// here-doc: o conteúdo é JSON cheio de aspas e barras, e `%s` o entrega
    /// literalmente sem o shell interpretar nada.
    public static func replaying(_ ndjson: String) -> FakeHarnessScript {
        let lines = ndjson.split(separator: "\n").filter { !$0.isEmpty }
        let body = lines.map { line in
            "printf '%s\\n' \(shellQuoted(String(line)))"
        }.joined(separator: "\n")
        return FakeHarnessScript(body: body + "\n")
    }

    /// Pede permissão, ESPERA a resposta no stdin, e só então termina.
    public static func permissionRequest() -> FakeHarnessScript {
        let request = #"""
        {"type":"control_request","request_id":"req-1","request":{"subtype":"can_use_tool","tool_name":"Write","input":{"file_path":"/tmp/a.txt"},"tool_use_id":"toolu_1"}}
        """#
        let result = #"{"type":"result","is_error":false,"stop_reason":"end_turn"}"#
        return FakeHarnessScript(body: """
        printf '%s\\n' \(shellQuoted(request))
        read -r _resposta
        printf '%s\\n' \(shellQuoted(result))
        """)
    }

    /// Sobe, não diz nada, e nunca sai sozinho. Para exercitar os prazos.
    ///
    /// Lê do stdin num laço em vez de dormir um número fixo: dormir daria um
    /// teste amarrado a um relógio, e a §5.5 é sobre o que acontece quando o
    /// harness NÃO responde, não sobre quanto tempo ele demora.
    public static func hanging() -> FakeHarnessScript {
        FakeHarnessScript(body: "while read -r _linha; do :; done\n")
    }

    /// Apaga o script. Chame num `defer`.
    public func cleanUp() {
        try? FileManager.default.removeItem(at: scriptURL)
    }

    /// Envolve em aspas simples, escapando as aspas simples que houver dentro.
    /// É a única citação que o `sh` trata como literal de verdade.
    private static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
```

> `ProcessTransport.Launch` é público em `HarnessCore` e este alvo já depende
> de `HarnessCore`. Confira a grafia exata dos rótulos do inicializador antes
> de escrever — leia o tipo.

- [ ] **Step 4: Rodar e verificar que passa**

```bash
cd Packages/HarnessKit && swift test --filter FakeHarnessScript
```
Esperado: PASSA (4 testes), sem warnings.

- [ ] **Step 5: Commit**

```bash
git add Packages/HarnessKit/Sources/HarnessTestSupport/FakeHarnessScript.swift \
        Packages/HarnessKit/Tests/HarnessCoreTests/FakeHarnessScriptTests.swift
git commit -m "test: um harness falso em sh, para exercitar o caminho inteiro sem gastar crédito"
```

---
