# ClaudeEventMapper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Traduzir as linhas JSON que o Claude Code escreve no stdout para os
dois fluxos da spec §4.4 — `SessionEvent` efêmero para o cockpit e
`TranscriptEntry` durável para o `Segment` — sem que um turno apareça duas
vezes no transcript.

**Architecture:** Um mapeador **sem estado**: uma função pura de uma linha
para zero ou mais saídas, com o relógio injetado. Cada tipo de linha tem UM
destino declarado — `stream_event` só alimenta a UI, `assistant`/`user`/
`result` só alimentam o transcript. O que o mapeador não reconhece vira
entrada `.unrecognized` com o payload inteiro preservado, nunca um erro.

**Tech Stack:** Swift 6, Swift Testing, zero dependências. Verificado contra
as quatro fixtures NDJSON gravadas na Etapa 2 — nenhum teste executa o
`claude`.

**Spec:** `docs/superpowers/specs/2026-09-16-devspace-fundacao-design.md`
(§4.1 vocabulário canônico, §4.2 modelo de domínio, §4.4 camadas e "Eventos
efêmeros vs. entradas duráveis", §5.4 tolerância, §7.1 estrutura de módulos)

**Contrato de fio observado:** `docs/superpowers/notes-2026-09-17-protocolo-observado.md`

## Global Constraints

- `swift-tools-version:6.0`; plataforma `.macOS(.v15)`; concorrência estrita do Swift 6.
- **Zero dependências externas** em `Package.swift`. Nenhuma task adiciona alvo ou dependência.
- Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`) — nunca XCTest.
- **Nenhum teste executa o `claude`.** Nem para "conferir", nem uma vez só: gravar
  as fixtures custou dinheiro real e `harness-probe record` se recusa a sobrescrever.
- **Sem asserções de tempo de relógio.** O relógio do mapeador é injetado; os testes
  passam um `Date` fixo.
- **Spec §7.1:** se um tipo não nomeia o Claude e um segundo adaptador precisaria dele,
  ele mora em `HarnessCore`. `HarnessCoreTests/ModuleBoundaryTests.swift` impõe isso —
  inclusive varrendo a *prosa* de `Sources/HarnessCore` atrás das palavras
  `claude`, `codex`, `opencode`. Comentário nenhum em `HarnessCore` pode nomear este CLI.
- **Requisito duro (spec §4.2):** o transcript é um registro semântico FIEL, não um log
  de exibição. O replay para outro harness depende de ele ser completo.
- **Degradar, não falhar (spec §5.4):** conteúdo desconhecido é preservado, nunca descartado
  nem propagado como erro.

---

## Decisões já fixadas (não reabrir durante a execução)

Estas foram decididas ao escrever o plano, a partir da medição do corpus. Um
implementador que discordar deve reportar a discordância no relatório, não
mudar a decisão.

### D1 — Uma fonte por destino

É a decisão que o plano da Etapa 4a deixou marcada como aberta, e a razão de
ela existir está no histograma do corpus: **298 linhas `stream_event` contra
17 linhas `assistant`**. O texto do assistente chega duas vezes, delta a delta
e consolidado. Se as duas fontes alimentassem o transcript, cada turno
apareceria centenas de vezes no store.

| Linha | → `SessionEvent` (efêmero) | → `TranscriptEntry` (durável) |
|---|---|---|
| `stream_event` | **sim** | **nunca** |
| `assistant` | não | sim (uma entrada por bloco de conteúdo) |
| `user` | não | sim (uma entrada por bloco) |
| `result` | não | sim (uma entrada) |
| `system/init` | sim | sim |
| `system/status` | sim | **nunca** |
| `system/thinking_tokens` | sim | **nunca** |
| `system/permission_denied` | não | sim |
| `rate_limit_event` | não | sim |
| `control_request`, `control_response` | não | não (é do `ControlChannel`) |

### D2 — `status` e `thinking_tokens` não são transcript

Dos 30 `system` do corpus, 21 são `status` (rótulo de spinner) e
`thinking_tokens` (estimativa corrente de tokens). São progresso de
exibição, não semântica: um replay para outro harness não ganha nada com
eles e o transcript ganha 21 linhas de ruído por sessão. Viram `SessionEvent`
e morrem ali.

`init`, `permission_denied` e `rate_limit_event` são duráveis: o primeiro é a
proveniência do segmento, o segundo é uma decisão de permissão de verdade, o
terceiro explica um turno que parou.

### D3 — `result.result` não vira texto do assistente

A linha `result` traz um campo `result` com a prosa final — que é byte a byte
a mesma coisa que o último bloco `text` da linha `assistant` que veio antes.
Mapeá-lo duplicaria o último parágrafo de todo turno. Ele fica só no `raw` da
entrada `.turnResult`.

### D4 — Granularidade do `raw`

Entrada derivada de um **bloco de conteúdo** (`text`, `thinking`, `tool_use`,
`tool_result`) carrega o bloco em `raw`. Entrada derivada da **linha inteira**
(`result`, `system/*`, `rate_limit_event`, `user` com conteúdo em string)
carrega a linha. É o payload fiel daquela entrada em cada caso; o modelo e o
usage da linha vivem no `Segment` e na entrada `.turnResult`.

### D5 — Vocabulário canônico vem do corpus

A tabela nome→verbo cobre exatamente os nomes que aparecem no array `tools` do
`system/init` gravado. Nome fora dela — ferramenta de MCP, `Task`, `Skill`,
uma que a CLI ganhe amanhã — devolve `nil`, que é a resposta honesta da spec
§4.1: inventar um verbo faria o handoff mandar ao próximo harness uma instrução
que ninguém pediu.

### D6 — O mapeador não tem estado

`content_block_delta` já traz `index` e o tipo do delta. Nada precisa ser
lembrado entre linhas. Isso é uma decisão de projeto a defender, não um
acidente: um mapeador com estado precisaria de um dono, de um ciclo de vida e
de um teste de reentrância. Se durante a execução parecer que falta estado,
isso é um achado para o relatório — não um `var` novo.

### D7 — `signature_delta` não vira evento

Os 5 `signature_delta` do corpus são a assinatura criptográfica do bloco de
raciocínio. Não há nada a mostrar delta a delta; a assinatura chega inteira no
`raw` do bloco `thinking` consolidado.

---

## File Structure

**Criar:**

| Arquivo | Responsabilidade |
|---|---|
| `Sources/HarnessCore/SessionEvent.swift` | `SessionEvent` + `MappedOutput` — o fluxo efêmero, neutro (§7.1) |
| `Sources/ClaudeHarness/ClaudeToolVocabulary.swift` | Nome de ferramenta deste CLI → `CanonicalTool` |
| `Sources/ClaudeHarness/ClaudeEventMapper.swift` | O mapeador: linha → `MappedOutput` |
| `Sources/ClaudeHarness/ClaudeEventMapper+Permission.swift` | Cunhagem das entradas de permissão a partir dos valores neutros |
| `Tests/HarnessCoreTests/SessionEventTests.swift` | O tipo efêmero e o `MappedOutput` |
| `Tests/ClaudeHarnessTests/ClaudeToolVocabularyTests.swift` | A tabela, varrida contra o array `tools` real |
| `Tests/ClaudeHarnessTests/ClaudeEventMapperTests.swift` | Unidade, com linhas sintéticas |
| `Tests/ClaudeHarnessTests/ClaudeEventMapperFixtureTests.swift` | As quatro fixtures, com contagens medidas |

**Modificar:**

| Arquivo | Mudança |
|---|---|
| `Sources/HarnessCore/JSONValue.swift` | Acessores `intValue`, `doubleValue`, `boolValue` |
| `Tests/HarnessCoreTests/ModuleBoundaryTests.swift` | Um caso a mais: os tipos efêmeros também são neutros |
| `Tests/HarnessCoreTests/JSONValueTests.swift` | Os acessores novos |

**Não mexer:** `Package.swift`, `ControlFrames.swift`, `ControlChannel.swift`,
`ProcessTransport.swift`, `FileTranscriptStore.swift`, as fixtures.

---

### Task 1: O fluxo efêmero e os acessores numéricos

**Files:**
- Create: `Packages/HarnessKit/Sources/HarnessCore/SessionEvent.swift`
- Modify: `Packages/HarnessKit/Sources/HarnessCore/JSONValue.swift` (acrescentar à extension pública existente)
- Test: `Packages/HarnessKit/Tests/HarnessCoreTests/SessionEventTests.swift`
- Test: `Packages/HarnessKit/Tests/HarnessCoreTests/JSONValueTests.swift` (acrescentar)
- Test: `Packages/HarnessKit/Tests/HarnessCoreTests/ModuleBoundaryTests.swift` (acrescentar um `@Test`)

**Interfaces:**
- Consumes: `TranscriptEntry` e `JSONValue`, de `HarnessCore`, já existentes.
- Produces: `SessionEvent` (enum de 6 casos), `MappedOutput` (struct com `events` e
  `entries`, mais `MappedOutput.empty`), e `JSONValue.intValue`/`.doubleValue`/`.boolValue`.
  Todas as tasks seguintes dependem destes nomes exatos.

**Por que em `HarnessCore` e não em `ClaudeHarness`:** o teste da §7.1. Nenhum
dos dois tipos nomeia harness nenhum, e o cockpit precisa de **um** tipo de
evento ou vira um cockpit por harness — exatamente o argumento que já moveu
`PermissionRequest` e `PermissionDecision` para cá. Este arquivo não pode
conter a palavra "claude" nem em comentário: `harnessCoreNeverNamesASpecificHarness`
varre a prosa.

- [ ] **Step 1: Escrever o teste que falha**

Em `Tests/HarnessCoreTests/SessionEventTests.swift`:

```swift
import Testing
import Foundation
import HarnessCore

@Test func aMappedOutputCarriesTheTwoStreamsSeparately() {
    let entry = TranscriptEntry(
        timestamp: Date(timeIntervalSince1970: 0),
        kind: .assistantText("pronto"),
        raw: .object(["type": .string("text")])
    )
    let output = MappedOutput(events: [.turnStarted], entries: [entry])

    #expect(output.events == [.turnStarted])
    #expect(output.entries.count == 1)
    #expect(output.entries[0].kind == .assistantText("pronto"))
}

@Test func anEmptyOutputCarriesNothing() {
    #expect(MappedOutput.empty.events.isEmpty)
    #expect(MappedOutput.empty.entries.isEmpty)
}

/// Os deltas se distinguem pelo índice do bloco: dois blocos de texto no mesmo
/// turno chegam intercalados e a UI precisa saber em qual rascunho escrever.
@Test func deltasAreDistinguishedByBlockIndex() {
    let a = SessionEvent.textDelta(blockIndex: 0, text: "oi")
    let b = SessionEvent.textDelta(blockIndex: 1, text: "oi")
    #expect(a != b)
}
```

E, em `Tests/HarnessCoreTests/JSONValueTests.swift`, acrescentar ao final:

```swift
@Test func theNumericAccessorsBridgeTheIntDoubleAmbiguity() {
    // Um consumidor JSON cuja representação numérica não distingue inteiro de
    // ponto flutuante escreve `0` onde o esquema diz "número". Ler um custo
    // como `.int(0)` e devolver `nil` de `doubleValue` perderia o valor.
    #expect(JSONValue.int(7).intValue == 7)
    #expect(JSONValue.int(7).doubleValue == 7.0)
    #expect(JSONValue.double(7.0).intValue == 7)
    #expect(JSONValue.double(7.5).intValue == nil)
    #expect(JSONValue.double(0.0227).doubleValue == 0.0227)
    #expect(JSONValue.bool(true).boolValue == true)
    #expect(JSONValue.string("7").intValue == nil)
    #expect(JSONValue.string("true").boolValue == nil)
    #expect(JSONValue.null.doubleValue == nil)
}
```

E, em `Tests/HarnessCoreTests/ModuleBoundaryTests.swift`, acrescentar ao final:

```swift
/// Mesmo alarme dos testes acima, agora para o fluxo efêmero. Este arquivo NÃO
/// importa `ClaudeHarness`: se `SessionEvent` ou `MappedOutput` acabarem lá,
/// ele deixa de compilar — e um segundo adaptador precisaria importar o
/// primeiro só para mandar um delta de texto à UI.
@Test func theEphemeralStreamTypesLiveInHarnessCore() {
    let output = MappedOutput(
        events: [.sessionInitialized(model: "m", harnessSessionID: "s"),
                 .notice(subtype: "status", text: "pensando")],
        entries: []
    )
    #expect(output.events.count == 2)
    #expect(output.entries.isEmpty)
}
```

- [ ] **Step 2: Rodar e verificar que falha**

```bash
cd Packages/HarnessKit && swift test --filter 'SessionEvent|JSONValue|ModuleBoundary'
```
Esperado: FALHA de compilação — `cannot find 'MappedOutput' in scope`.

- [ ] **Step 3: Escrever `SessionEvent.swift`**

```swift
import Foundation

/// Um acontecimento que a UI consome enquanto ele acontece.
///
/// Efêmero de propósito (spec §4.4): `--include-partial-messages` emite deltas
/// de token, e se cada delta virasse uma entrada um turno viraria centenas de
/// entradas no store. Este tipo vai para o cockpit delta a delta e morre ali;
/// o que sobrevive é a `TranscriptEntry`, que nasce consolidada quando o turno
/// fecha.
///
/// **Não conforma a `Codable`, e isso é deliberado.** Conformar convidaria a
/// persistir — e persistir este fluxo ao lado do durável é exatamente a
/// duplicação que a §4.4 existe para impedir. Se um dia algo aqui precisar
/// sobreviver a um reinício, o lugar dele é uma `TranscriptEntry`.
public enum SessionEvent: Sendable, Equatable {
    /// O harness subiu e disse com que modelo, e em que sessão dele.
    ///
    /// O `harnessSessionID` vem como `String` porque é a grafia do harness, não
    /// a nossa: quem compara com o `Segment.harnessSessionID` que nós geramos é
    /// a camada de sessão, e uma divergência ali significa que o resume não
    /// pegou a sessão que pedimos.
    case sessionInitialized(model: String, harnessSessionID: String)
    /// Um turno começou. O cockpit limpa os rascunhos de bloco.
    case turnStarted
    /// Um pedaço de texto do assistente.
    case textDelta(blockIndex: Int, text: String)
    /// Um pedaço do raciocínio do assistente.
    case thinkingDelta(blockIndex: Int, text: String)
    /// Um pedaço do input de uma ferramenta, como JSON ainda incompleto.
    ///
    /// Chega em fatias que sozinhas não são JSON válido — é material de
    /// exibição ("montando a chamada…"), não de análise. O input completo chega
    /// na entrada `.toolCall` quando o bloco fecha.
    case toolInputDelta(blockIndex: Int, partialJSON: String)
    /// Progresso que o harness relata e que não é semântica da conversa.
    case notice(subtype: String, text: String)
}

/// O que sai do mapeador ao consumir uma linha do harness.
///
/// Os dois fluxos da spec §4.4, separados no tipo em vez de num único canal
/// que o chamador filtra: `events` vai para o cockpit, `entries` vai para o
/// `Segment`. Uma linha pode produzir nenhum, um ou vários de cada.
public struct MappedOutput: Sendable, Equatable {
    /// Efêmero — para a UI.
    public var events: [SessionEvent]
    /// Durável — para o transcript.
    public var entries: [TranscriptEntry]

    public init(events: [SessionEvent] = [], entries: [TranscriptEntry] = []) {
        self.events = events
        self.entries = entries
    }

    public static let empty = MappedOutput()
}
```

- [ ] **Step 4: Acrescentar os acessores em `JSONValue.swift`**

Dentro da `public extension JSONValue` que já existe, depois de `arrayValue`:

```swift
    /// O valor como inteiro.
    ///
    /// Aceita `.double` com resto fracionário zero pela mesma razão que a doc
    /// do tipo já explica no sentido inverso: do outro lado do pipe pode haver
    /// um runtime cuja representação numérica não distingue `1` de `1.0`, e o
    /// mesmo campo pode chegar de um jeito ou do outro entre versões. Um
    /// `.double(7.5)` continua devolvendo `nil` — isso é um erro de esquema,
    /// não uma ambiguidade de grafia.
    var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int(exactly: d)
        default: return nil
        }
    }

    /// O valor como ponto flutuante. Aceita `.int` pelo mesmo motivo acima —
    /// um custo de zero chega como `0`, não como `0.0`.
    var doubleValue: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        default: return nil
        }
    }

    /// O valor como booleano. Estrito: a string `"true"` não é um booleano.
    var boolValue: Bool? {
        guard case .bool(let b) = self else { return nil }
        return b
    }
```

- [ ] **Step 5: Rodar e verificar que passa**

```bash
cd Packages/HarnessKit && swift test --filter 'SessionEvent|JSONValue|ModuleBoundary'
```
Esperado: PASSA, sem warnings.

- [ ] **Step 6: Commit**

```bash
git add Packages/HarnessKit/Sources/HarnessCore/SessionEvent.swift \
        Packages/HarnessKit/Sources/HarnessCore/JSONValue.swift \
        Packages/HarnessKit/Tests/HarnessCoreTests/SessionEventTests.swift \
        Packages/HarnessKit/Tests/HarnessCoreTests/JSONValueTests.swift \
        Packages/HarnessKit/Tests/HarnessCoreTests/ModuleBoundaryTests.swift
git commit -m "feat(core): fluxo efêmero SessionEvent e acessores numéricos de JSONValue"
```

---

### Task 2: O vocabulário canônico deste CLI

**Files:**
- Create: `Packages/HarnessKit/Sources/ClaudeHarness/ClaudeToolVocabulary.swift`
- Test: `Packages/HarnessKit/Tests/ClaudeHarnessTests/ClaudeToolVocabularyTests.swift`

**Interfaces:**
- Consumes: `CanonicalTool`, de `HarnessCore`.
- Produces: `ClaudeToolVocabulary.canonical(for rawName: String) -> CanonicalTool?`
  — `internal`, não `public`: o único chamador é o mapeador, no mesmo módulo.

**A tabela, e de onde ela vem.** O array `tools` do `system/init` gravado em
`hello.ndjson` lista as 25 ferramentas que esta versão do CLI (2.1.236) expõe.
Destas, sete têm verbo equivalente no vocabulário da spec §4.1:

| Nome no CLI | Verbo canônico |
|---|---|
| `Read` | `.read` |
| `Write` | `.write` |
| `Edit` | `.edit` |
| `NotebookEdit` | `.edit` |
| `Bash` | `.execute` |
| `WebSearch` | `.search` |
| `WebFetch` | `.fetch` |

As outras dezoito — `Task`, `Skill`, `ToolSearch`, `Monitor`, `CronCreate`,
`SendMessage` e companhia — não têm equivalente, e nenhuma ferramenta de MCP
(`mcp__servidor__ferramenta`) tem. Todas devolvem `nil`.

Não acrescente nomes que não estão nessa lista (`Glob`, `Grep`, `MultiEdit`,
`NotebookRead` e outros que outras versões já tiveram). Um nome que esta
versão não emite é uma linha que nenhum teste pode exercitar contra o corpus,
e a degradação para `nil` já cobre o caso corretamente se ele voltar.

- [ ] **Step 1: Escrever o teste que falha**

Em `Tests/ClaudeHarnessTests/ClaudeToolVocabularyTests.swift`:

```swift
import Testing
import Foundation
import HarnessCore
@testable import ClaudeHarness

@Test func theSevenMappedToolsGetTheirCanonicalVerb() {
    #expect(ClaudeToolVocabulary.canonical(for: "Read") == .read)
    #expect(ClaudeToolVocabulary.canonical(for: "Write") == .write)
    #expect(ClaudeToolVocabulary.canonical(for: "Edit") == .edit)
    #expect(ClaudeToolVocabulary.canonical(for: "NotebookEdit") == .edit)
    #expect(ClaudeToolVocabulary.canonical(for: "Bash") == .execute)
    #expect(ClaudeToolVocabulary.canonical(for: "WebSearch") == .search)
    #expect(ClaudeToolVocabulary.canonical(for: "WebFetch") == .fetch)
}

/// Spec §4.1: inventar um verbo faria o handoff mandar ao próximo harness uma
/// instrução que ninguém pediu. `nil` é a resposta honesta.
@Test func aToolWithoutAnEquivalentVerbIsNil() {
    #expect(ClaudeToolVocabulary.canonical(for: "Task") == nil)
    #expect(ClaudeToolVocabulary.canonical(for: "Skill") == nil)
    #expect(ClaudeToolVocabulary.canonical(for: "mcp__figma__get_file") == nil)
    #expect(ClaudeToolVocabulary.canonical(for: "") == nil)
}

/// O casamento é exato, não por prefixo nem sem distinguir maiúsculas: o CLI
/// escreve os nomes numa grafia só, e afrouxar aqui faria uma ferramenta
/// chamada `ReadOnlyThing` virar `.read`.
@Test func theMatchIsExact() {
    #expect(ClaudeToolVocabulary.canonical(for: "read") == nil)
    #expect(ClaudeToolVocabulary.canonical(for: "ReadFile") == nil)
    #expect(ClaudeToolVocabulary.canonical(for: " Bash") == nil)
}

/// A tabela é derivada do array `tools` do `system/init` real. Este teste lê
/// esse array da fixture e fixa quais nomes têm verbo — se uma regravação
/// futura trouxer uma ferramenta nova, ele aponta exatamente onde decidir.
@Test func theTableAgreesWithTheRecordedToolList() throws {
    // Mesmo acesso que `ControlFramesTests.fixtureLines` já usa.
    let url = try #require(Bundle.module.url(
        forResource: "Fixtures/hello", withExtension: "ndjson"))
    let firstLine = try #require(
        String(contentsOf: url, encoding: .utf8).split(separator: "\n").first)
    let initLine = try JSONDecoder().decode(JSONValue.self, from: Data(firstLine.utf8))
    #expect(initLine["subtype"]?.stringValue == "init")

    let tools = try #require(initLine["tools"]?.arrayValue).compactMap(\.stringValue)
    #expect(tools.count == 25)

    let mapped = Set(tools.filter { ClaudeToolVocabulary.canonical(for: $0) != nil })
    #expect(mapped == ["Read", "Write", "Edit", "NotebookEdit", "Bash", "WebSearch", "WebFetch"])
}
```

- [ ] **Step 2: Rodar e verificar que falha**

```bash
cd Packages/HarnessKit && swift test --filter ClaudeToolVocabulary
```
Esperado: FALHA de compilação — `cannot find 'ClaudeToolVocabulary' in scope`.

- [ ] **Step 3: Escrever `ClaudeToolVocabulary.swift`**

```swift
import HarnessCore

/// Os nomes de ferramenta deste CLI traduzidos para o vocabulário canônico da
/// spec §4.1.
///
/// Mora em `ClaudeHarness` porque é específico deste harness — e é o exemplo
/// mais limpo da regra da §7.1: `CanonicalTool` é neutro e mora no núcleo;
/// saber que este CLI chama `Bash` o que outro chamará de outra coisa é
/// conhecimento do adaptador.
///
/// A tabela cobre exatamente os nomes do array `tools` do `system/init`
/// gravado (CLI 2.1.236). Nome fora dela devolve `nil` — que é a resposta
/// honesta e a que o `ToolCall.canonical` já existe para carregar; o
/// `rawName` preserva a grafia original e o `raw` da entrada preserva o bloco
/// inteiro, então nada se perde ao não conhecer um verbo.
enum ClaudeToolVocabulary {
    static func canonical(for rawName: String) -> CanonicalTool? {
        switch rawName {
        case "Read": return .read
        case "Write": return .write
        case "Edit", "NotebookEdit": return .edit
        case "Bash": return .execute
        case "WebSearch": return .search
        case "WebFetch": return .fetch
        default: return nil
        }
    }
}
```

- [ ] **Step 4: Rodar e verificar que passa**

```bash
cd Packages/HarnessKit && swift test --filter ClaudeToolVocabulary
```
Esperado: PASSA (4 testes), sem warnings.

- [ ] **Step 5: Commit**

```bash
git add Packages/HarnessKit/Sources/ClaudeHarness/ClaudeToolVocabulary.swift \
        Packages/HarnessKit/Tests/ClaudeHarnessTests/ClaudeToolVocabularyTests.swift
git commit -m "feat(claude): vocabulário canônico das ferramentas deste CLI"
```

---

### Task 3: O mapeador, o caminho efêmero e a degradação

**Files:**
- Create: `Packages/HarnessKit/Sources/ClaudeHarness/ClaudeEventMapper.swift`
- Test: `Packages/HarnessKit/Tests/ClaudeHarnessTests/ClaudeEventMapperTests.swift`

**Interfaces:**
- Consumes: `SessionEvent`, `MappedOutput`, `JSONValue.intValue` (Task 1).
- Produces:
  - `ClaudeEventMapper.init(now: @escaping @Sendable () -> Date = Date.init)`
  - `func map(_ line: JSONValue) -> MappedOutput`
  - `func map(line data: Data) -> MappedOutput`
  - `internal func unrecognized(_ discriminator: String, _ payload: JSONValue, at: Date?) -> TranscriptEntry`
  - A constante `ClaudeEventMapper.discriminatorPrefix = "claude:"`

  As Tasks 4 e 5 acrescentam ramos ao `switch` de `map(_:)` e usam
  `unrecognized(_:_:at:)`. Nenhuma delas muda estas assinaturas.

**O prefixo `claude:` nos discriminadores — não o remova.** Uma linha que este
binário não sabe mapear vira `TranscriptEntry.Kind.unrecognized(discriminator:payload:)`,
e esse caso tem um contrato de idempotência: reencodar reemite o discriminador
original como chave JSON. Sem prefixo, uma linha futura com
`"type":"turnResult"` viraria `.unrecognized(discriminator: "turnResult", …)` e
gravaria `{"turnResult": <linha crua do CLI>}` — que um leitor reconhece como
o caso conhecido `turnResult` e tenta decodificar como `TurnResult`,
estourando `DecodingError` na entrada inteira. O prefixo torna a colisão
impossível por construção: nenhum caso de `Kind` se chama `claude:qualquer
coisa`.

**Relógio injetado.** Só as linhas `assistant` e `user` trazem `timestamp`;
`system`, `result`, `stream_event` e `rate_limit_event` não trazem nenhum. O
mapeador recebe o relógio por parâmetro, e é isso que permite testar sem
asserção de tempo de parede.

- [ ] **Step 1: Escrever o teste que falha**

Em `Tests/ClaudeHarnessTests/ClaudeEventMapperTests.swift`:

```swift
import Testing
import Foundation
@testable import HarnessCore
@testable import ClaudeHarness

/// `@testable` em `HarnessCore` para alcançar
/// `TranscriptEntry.Kind.knownDiscriminators`, que é `internal`.

/// Um instante fixo: nenhuma asserção deste arquivo depende do relógio de
/// parede.
let fixedNow = Date(timeIntervalSince1970: 1_000_000)

func makeMapper() -> ClaudeEventMapper {
    ClaudeEventMapper(now: { fixedNow })
}

func json(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

// MARK: - Deltas

@Test func aTextDeltaBecomesAnEphemeralEventAndNothingDurable() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"stream_event","event":{"type":"content_block_delta","index":0,
     "delta":{"type":"text_delta","text":"Olá"}},"session_id":"s"}
    """#))
    #expect(out.events == [.textDelta(blockIndex: 0, text: "Olá")])
    #expect(out.entries.isEmpty)
}

@Test func aThinkingDeltaReadsTheThinkingFieldNotTheTextField() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"stream_event","event":{"type":"content_block_delta","index":1,
     "delta":{"type":"thinking_delta","thinking":"hmm"}}}
    """#))
    #expect(out.events == [.thinkingDelta(blockIndex: 1, text: "hmm")])
}

@Test func anInputJSONDeltaCarriesThePartialJSONVerbatim() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"stream_event","event":{"type":"content_block_delta","index":2,
     "delta":{"type":"input_json_delta","partial_json":"{\"comm"}}}
    """#))
    #expect(out.events == [.toolInputDelta(blockIndex: 2, partialJSON: "{\"comm")])
}

/// D7: a assinatura do bloco de raciocínio não tem nada a mostrar delta a
/// delta; ela chega inteira no `raw` do bloco consolidado.
@Test func aSignatureDeltaProducesNothing() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"stream_event","event":{"type":"content_block_delta","index":1,
     "delta":{"type":"signature_delta","signature":"abc"}}}
    """#))
    #expect(out == .empty)
}

@Test func messageStartBecomesTurnStarted() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"stream_event","event":{"type":"message_start",
     "message":{"model":"claude-opus-5","content":[]}}}
    """#))
    #expect(out.events == [.turnStarted])
    #expect(out.entries.isEmpty)
}

/// Os quadros de moldura do stream não interessam a ninguém: o começo e o fim
/// de bloco a UI infere do índice dos deltas, e o fim de mensagem chega
/// consolidado na linha `assistant`.
@Test func theStreamFramingEventsProduceNothing() throws {
    for frame in [
        #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
        #"{"type":"content_block_stop","index":0}"#,
        #"{"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#,
        #"{"type":"message_stop"}"#,
    ] {
        let out = makeMapper().map(try json(#"{"type":"stream_event","event":\#(frame)}"#))
        #expect(out == .empty, "quadro inesperadamente mapeado: \(frame)")
    }
}

/// D1, o invariante que este plano existe para garantir: o fluxo de deltas
/// NUNCA alimenta o transcript. São 298 `stream_event` contra 17 `assistant`
/// no corpus — se os dois alimentassem, todo turno apareceria centenas de
/// vezes no store.
@Test func noStreamEventEverProducesADurableEntry() throws {
    let malformed = [
        #"{"type":"stream_event"}"#,
        #"{"type":"stream_event","event":{}}"#,
        #"{"type":"stream_event","event":{"type":"content_block_delta"}}"#,
        #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta"}}}"#,
        #"{"type":"stream_event","event":{"type":"algo_novo"}}"#,
    ]
    for line in malformed {
        #expect(try makeMapper().map(json(line)).entries.isEmpty, "linha: \(line)")
    }
}

// MARK: - Degradação

@Test func anUnknownLineTypeIsPreservedNotDropped() throws {
    let line = try json(#"{"type":"future_thing","payload":{"a":1}}"#)
    let out = makeMapper().map(line)
    #expect(out.events.isEmpty)
    let entry = try #require(out.entries.first)
    #expect(out.entries.count == 1)
    #expect(entry.kind == .unrecognized(discriminator: "claude:future_thing", payload: line))
    #expect(entry.raw == line)
    #expect(entry.timestamp == fixedNow)
}

@Test func aLineWithoutATypeIsPreservedToo() throws {
    let line = try json(#"{"sem":"tipo"}"#)
    let entry = try #require(makeMapper().map(line).entries.first)
    #expect(entry.kind == .unrecognized(discriminator: "claude:line", payload: line))
}

@Test func aLineThatIsNotJSONIsPreservedAsText() {
    let out = makeMapper().map(line: Data("isto não é json".utf8))
    #expect(out.entries.count == 1)
    #expect(out.entries.first?.kind
            == .unrecognized(discriminator: "claude:nonJSON", payload: .string("isto não é json")))
}

/// O prefixo é o que impede um `"type":"turnResult"` futuro de virar um
/// discriminador que um leitor confunde com o caso conhecido `turnResult` —
/// ver a nota da task.
@Test func theDiscriminatorNeverCollidesWithAKnownKind() throws {
    let line = try json(#"{"type":"turnResult"}"#)
    guard case .unrecognized(let discriminator, _) =
            try #require(makeMapper().map(line).entries.first).kind else {
        Issue.record("esperava .unrecognized"); return
    }
    #expect(discriminator == "claude:turnResult")
    #expect(!TranscriptEntry.Kind.knownDiscriminators.contains(discriminator))
}

@Test func aControlFrameProducesNothingBecauseTheControlChannelOwnsIt() throws {
    #expect(try makeMapper().map(json(#"{"type":"control_request","request_id":"1"}"#)) == .empty)
    #expect(try makeMapper().map(json(#"{"type":"control_response","response":{}}"#)) == .empty)
}
```

> `TranscriptEntry.Kind.knownDiscriminators` é `internal` em `HarnessCore`. Se o
> `@testable import ClaudeHarness` não o alcançar a partir deste alvo,
> acrescente `@testable import HarnessCore` ao topo do arquivo.

- [ ] **Step 2: Rodar e verificar que falha**

```bash
cd Packages/HarnessKit && swift test --filter ClaudeEventMapperTests
```
Esperado: FALHA de compilação — `cannot find 'ClaudeEventMapper' in scope`.

- [ ] **Step 3: Escrever `ClaudeEventMapper.swift`**

```swift
import Foundation
import HarnessCore

/// Traduz as linhas do stdout deste CLI para os dois fluxos da spec §4.4.
///
/// **Sem estado, de propósito.** `content_block_delta` já traz o índice do
/// bloco e o tipo do delta; nada precisa ser lembrado entre linhas. Um
/// mapeador com estado precisaria de dono, de ciclo de vida e de um teste de
/// reentrância — e a consolidação, que é o único lugar onde estado pareceria
/// necessário, o próprio CLI já faz por nós: ele reemite o turno inteiro na
/// linha `assistant`.
///
/// **Uma fonte por destino.** É o invariante central: `stream_event` só
/// alimenta `events`, `assistant`/`user`/`result` só alimentam `entries`.
/// Medido no corpus: 298 `stream_event` contra 17 `assistant` — as duas fontes
/// carregam o MESMO texto, e alimentar as duas ao transcript multiplicaria
/// cada turno por centenas.
public struct ClaudeEventMapper: Sendable {
    /// Prefixo de todo discriminador que este mapeador cunha.
    ///
    /// Existe para tornar impossível a colisão com um caso conhecido de
    /// `TranscriptEntry.Kind`: sem ele, uma linha `{"type":"turnResult"}` de
    /// uma versão futura viraria `{"turnResult": <linha crua>}` no disco, que
    /// um leitor reconheceria como o caso conhecido e tentaria decodificar
    /// como `TurnResult` — estourando a entrada inteira. Nenhum caso de `Kind`
    /// se chama `claude:*`.
    static let discriminatorPrefix = "claude:"

    /// `internal`, não `private`: a extension durável da Task 4 e o arquivo
    /// `ClaudeEventMapper+Permission.swift` da Task 5 precisam dele, e um
    /// `private` obrigaria tudo a caber num arquivo só. Segue invisível fora
    /// do módulo.
    let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    /// Mapeia uma linha já decodificada.
    public func map(_ line: JSONValue) -> MappedOutput {
        guard let type = line["type"]?.stringValue else {
            return MappedOutput(entries: [unrecognized("line", line)])
        }
        switch type {
        case "stream_event":
            return ephemeral(line)
        case "control_request", "control_response":
            // O `ControlChannel` é o dono destes quadros (Etapa 3). Mapeá-los
            // aqui também poria o mesmo pedido de permissão duas vezes no
            // transcript.
            return .empty
        default:
            return MappedOutput(entries: [unrecognized(type, line)])
        }
    }

    /// Mapeia uma linha crua do transporte.
    ///
    /// Uma linha que não é JSON não é um erro a propagar: a spec §5.4 manda
    /// preservar. Os bytes viram `.string` — decodificados como UTF-8 com
    /// substituição, então uma sequência inválida vira U+FFFD em vez de
    /// derrubar a linha.
    public func map(line data: Data) -> MappedOutput {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            let text = JSONValue.string(String(decoding: data, as: UTF8.self))
            return MappedOutput(entries: [unrecognized("nonJSON", text)])
        }
        return map(value)
    }

    // MARK: - Efêmero

    private func ephemeral(_ line: JSONValue) -> MappedOutput {
        guard let event = line["event"], let kind = event["type"]?.stringValue else {
            return .empty
        }
        switch kind {
        case "message_start":
            return MappedOutput(events: [.turnStarted])
        case "content_block_delta":
            return MappedOutput(events: delta(event).map { [$0] } ?? [])
        default:
            // content_block_start, content_block_stop, message_delta,
            // message_stop: moldura do stream. O começo e o fim de um bloco a
            // UI infere do índice dos deltas, e o fim da mensagem chega
            // consolidado na linha `assistant`.
            return .empty
        }
    }

    private func delta(_ event: JSONValue) -> SessionEvent? {
        guard let index = event["index"]?.intValue,
              let delta = event["delta"],
              let kind = delta["type"]?.stringValue
        else { return nil }

        switch kind {
        case "text_delta":
            guard let text = delta["text"]?.stringValue else { return nil }
            return .textDelta(blockIndex: index, text: text)
        case "thinking_delta":
            guard let text = delta["thinking"]?.stringValue else { return nil }
            return .thinkingDelta(blockIndex: index, text: text)
        case "input_json_delta":
            guard let partial = delta["partial_json"]?.stringValue else { return nil }
            return .toolInputDelta(blockIndex: index, partialJSON: partial)
        default:
            // signature_delta e o que a API inventar depois: nada a mostrar
            // delta a delta. O conteúdo chega inteiro no bloco consolidado.
            return nil
        }
    }

    // MARK: - Degradação

    /// Preserva o que não sabemos mapear (spec §5.4).
    ///
    /// `at` só é passado quando a linha trouxe `timestamp` próprio; senão vale
    /// o relógio injetado.
    func unrecognized(_ discriminator: String, _ payload: JSONValue,
                      at moment: Date? = nil) -> TranscriptEntry {
        TranscriptEntry(
            timestamp: moment ?? now(),
            kind: .unrecognized(discriminator: Self.discriminatorPrefix + discriminator,
                                payload: payload),
            raw: payload
        )
    }
}
```

- [ ] **Step 4: Rodar e verificar que passa**

```bash
cd Packages/HarnessKit && swift test --filter ClaudeEventMapperTests
```
Esperado: PASSA (12 testes), sem warnings.

- [ ] **Step 5: Commit**

```bash
git add Packages/HarnessKit/Sources/ClaudeHarness/ClaudeEventMapper.swift \
        Packages/HarnessKit/Tests/ClaudeHarnessTests/ClaudeEventMapperTests.swift
git commit -m "feat(claude): mapeador sem estado, caminho efêmero e degradação"
```

---

### Task 4: O caminho durável da conversa

**Files:**
- Modify: `Packages/HarnessKit/Sources/ClaudeHarness/ClaudeEventMapper.swift` (acrescentar ramos ao `switch` de `map(_:)` e uma extension)
- Test: `Packages/HarnessKit/Tests/ClaudeHarnessTests/ClaudeEventMapperTests.swift` (acrescentar ao final)

**Interfaces:**
- Consumes: `unrecognized(_:_:at:)` e o `switch` de `map(_:)` (Task 3);
  `ClaudeToolVocabulary.canonical(for:)` (Task 2); `ToolCall`, `ToolResult`,
  `TurnResult`, `UsageTotals`, de `HarnessCore`.
- Produces: nada de novo na superfície pública. Acrescenta os ramos
  `"assistant"`, `"user"` e `"result"` ao `switch` que a Task 3 escreveu,
  removendo-os do `default`.

**A linha `user` com conteúdo em string.** As 8 linhas `user` do corpus são
todas blocos `tool_result` — o CLI observado não ecoa de volta o turno que nós
escrevemos no stdin. O ramo da string existe mesmo assim, e o teste dele é
sintético: `{"role":"user","content":"<texto>"}` é inequivocamente uma
mensagem do usuário, o `role` diz isso, e mapear um campo que significa
exatamente o que o caso significa não é inventar nada. Custa três linhas e
tira um caso de degradação conhecido do caminho. Está documentado no código
que o corpus não o exercita.

**`result.result` não vira entrada** (D3): o campo traz a mesma prosa do
último bloco `text` da linha `assistant` anterior. Ele fica só no `raw` da
entrada `.turnResult`. O teste `theFinalProseIsNotDuplicatedAsAssistantText`
fixa isso.

- [ ] **Step 1: Escrever o teste que falha**

Acrescentar ao final de `Tests/ClaudeHarnessTests/ClaudeEventMapperTests.swift`:

```swift
// MARK: - Durável: assistant

@Test func anAssistantTextBlockBecomesOneDurableEntryAndNoEvent() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"assistant","timestamp":"2026-09-17T02:16:56.133Z",
     "message":{"role":"assistant","content":[{"type":"text","text":"OK"}]}}
    """#))
    #expect(out.events.isEmpty)
    #expect(out.entries.count == 1)
    #expect(out.entries[0].kind == .assistantText("OK"))
    // D4: o `raw` de uma entrada derivada de bloco é o bloco.
    #expect(out.entries[0].raw == .object(["type": .string("text"), "text": .string("OK")]))
}

/// A linha traz `timestamp` próprio — o relógio injetado não é usado.
@Test func anAssistantEntryUsesTheLineTimestamp() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"assistant","timestamp":"2026-09-17T02:20:59.447Z",
     "message":{"content":[{"type":"text","text":"x"}]}}
    """#))
    // Tolerância, não igualdade: `Date` compara `Double`, e o valor que sai
    // do parser não é bit a bit o mesmo que o literal. Isto afere a análise do
    // carimbo, não o relógio de parede.
    let expected = Date(timeIntervalSince1970: 1_789_611_659.447)
    #expect(abs(out.entries[0].timestamp.timeIntervalSince(expected)) < 0.001)
}

@Test func anAssistantTimestampThatDoesNotParseFallsBackToTheClock() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"assistant","timestamp":"ontem de tarde",
     "message":{"content":[{"type":"text","text":"x"}]}}
    """#))
    #expect(out.entries[0].timestamp == fixedNow)
}

@Test func aThinkingBlockBecomesAssistantThinking() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"assistant","message":{"content":[
      {"type":"thinking","thinking":"deixa eu ver","signature":"abc"}]}}
    """#))
    #expect(out.entries.count == 1)
    #expect(out.entries[0].kind == .assistantThinking("deixa eu ver"))
    // A assinatura sobrevive no raw, que é o que o D7 prometeu.
    #expect(out.entries[0].raw["signature"]?.stringValue == "abc")
}

@Test func aToolUseBlockBecomesAToolCallWithItsCanonicalVerb() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"assistant","message":{"content":[
      {"type":"tool_use","id":"toolu_1","name":"Bash",
       "input":{"command":"ls","description":"listar"}}]}}
    """#))
    guard case .toolCall(let call) = try #require(out.entries.first).kind else {
        Issue.record("esperava .toolCall"); return
    }
    #expect(call.id == "toolu_1")
    #expect(call.rawName == "Bash")
    #expect(call.canonical == .execute)
    #expect(call.input["command"]?.stringValue == "ls")
}

@Test func aToolWithoutACanonicalVerbKeepsItsRawName() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"assistant","message":{"content":[
      {"type":"tool_use","id":"toolu_2","name":"Skill","input":{}}]}}
    """#))
    guard case .toolCall(let call) = try #require(out.entries.first).kind else {
        Issue.record("esperava .toolCall"); return
    }
    #expect(call.canonical == nil)
    #expect(call.rawName == "Skill")
}

@Test func aMessageWithSeveralBlocksBecomesOneEntryPerBlockInOrder() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"assistant","message":{"content":[
      {"type":"thinking","thinking":"hm"},
      {"type":"text","text":"vou listar"},
      {"type":"tool_use","id":"t1","name":"Bash","input":{}}]}}
    """#))
    #expect(out.entries.count == 3)
    #expect(out.entries[0].kind == .assistantThinking("hm"))
    #expect(out.entries[1].kind == .assistantText("vou listar"))
    if case .toolCall = out.entries[2].kind {} else { Issue.record("esperava .toolCall em 2") }
}

/// Spec §5.4: nenhum bloco é descartado, nem o que não sabemos ler.
@Test func anUnknownOrMalformedBlockIsPreservedNotDropped() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"assistant","message":{"content":[
      {"type":"bloco_novo","seja_o_que_for":1},
      {"type":"text"},
      {"sem":"tipo"}]}}
    """#))
    #expect(out.entries.count == 3)
    for entry in out.entries {
        guard case .unrecognized(let discriminator, _) = entry.kind else {
            Issue.record("esperava .unrecognized, veio \(entry.kind)"); continue
        }
        #expect(discriminator.hasPrefix("claude:content/"))
    }
}

@Test func anAssistantLineWithoutContentIsPreservedWhole() throws {
    let line = try json(#"{"type":"assistant","message":{"role":"assistant"}}"#)
    let entry = try #require(makeMapper().map(line).entries.first)
    #expect(entry.kind == .unrecognized(discriminator: "claude:assistant", payload: line))
}

// MARK: - Durável: user

@Test func aToolResultBlockBecomesAToolResultEntry() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"user","timestamp":"2026-09-17T02:20:59.447Z","message":{"role":"user","content":[
      {"type":"tool_result","tool_use_id":"toolu_1","content":"total 16","is_error":false}]}}
    """#))
    guard case .toolResult(let result) = try #require(out.entries.first).kind else {
        Issue.record("esperava .toolResult"); return
    }
    #expect(result.callID == "toolu_1")
    #expect(result.isError == false)
    #expect(result.content.stringValue == "total 16")
}

/// `is_error` chega ausente em parte das linhas do corpus. Ausente significa
/// "deu certo" — não "não sabemos".
@Test func aToolResultWithoutIsErrorIsNotAnError() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"user","message":{"content":[
      {"type":"tool_result","tool_use_id":"t","content":"ok"}]}}
    """#))
    guard case .toolResult(let result) = try #require(out.entries.first).kind else {
        Issue.record("esperava .toolResult"); return
    }
    #expect(result.isError == false)
}

@Test func aFailedToolResultCarriesItsErrorFlag() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"user","message":{"content":[
      {"type":"tool_result","tool_use_id":"t","content":"blocked","is_error":true}]}}
    """#))
    guard case .toolResult(let result) = try #require(out.entries.first).kind else {
        Issue.record("esperava .toolResult"); return
    }
    #expect(result.isError == true)
}

/// Forma sintética: o CLI observado não ecoa o turno que escrevemos. Ver a
/// nota da task.
@Test func aUserLineWithStringContentBecomesAUserMessage() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"user","message":{"role":"user","content":"liste a pasta"}}
    """#))
    #expect(out.entries.count == 1)
    #expect(out.entries[0].kind == .userMessage(text: "liste a pasta", attachments: []))
}

// MARK: - Durável: result

@Test func aResultLineBecomesATurnResultWithItsUsage() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"result","subtype":"success","is_error":false,"stop_reason":"end_turn",
     "result":"OK","total_cost_usd":0.133027,
     "usage":{"input_tokens":2,"output_tokens":4,
              "cache_read_input_tokens":0,"cache_creation_input_tokens":13197}}
    """#))
    #expect(out.events.isEmpty)
    #expect(out.entries.count == 1)
    guard case .turnResult(let turn) = out.entries[0].kind else {
        Issue.record("esperava .turnResult"); return
    }
    #expect(turn.usage == UsageTotals(inputTokens: 2, outputTokens: 4,
                                      cacheReadTokens: 0, cacheCreationTokens: 13197,
                                      costUSD: 0.133027))
    #expect(turn.stopReason == "end_turn")
    #expect(turn.isError == false)
    // A linha não traz timestamp: vale o relógio injetado.
    #expect(out.entries[0].timestamp == fixedNow)
}

/// D3: a prosa final da linha `result` é a MESMA do último bloco `text` da
/// linha `assistant`. Mapeá-la duplicaria o último parágrafo de todo turno.
@Test func theFinalProseIsNotDuplicatedAsAssistantText() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"result","is_error":false,"result":"OK","usage":{}}
    """#))
    #expect(out.entries.count == 1)
    for entry in out.entries {
        if case .assistantText = entry.kind { Issue.record("prosa final duplicada") }
    }
    // Mas continua recuperável: o raw guarda a linha inteira.
    #expect(out.entries[0].raw["result"]?.stringValue == "OK")
}

@Test func aResultWithoutUsageCountsZeroInsteadOfFailing() throws {
    let out = makeMapper().map(try json(#"{"type":"result","is_error":true}"#))
    guard case .turnResult(let turn) = try #require(out.entries.first).kind else {
        Issue.record("esperava .turnResult"); return
    }
    #expect(turn.usage == .zero)
    #expect(turn.isError == true)
    #expect(turn.stopReason == nil)
}
```

- [ ] **Step 2: Rodar e verificar que falha**

```bash
cd Packages/HarnessKit && swift test --filter ClaudeEventMapperTests
```
Esperado: FALHA — as entradas vêm como `.unrecognized(discriminator: "claude:assistant", …)`
porque o `switch` ainda cai no `default`.

- [ ] **Step 3: Acrescentar os ramos ao `switch` de `map(_:)`**

Entre o caso `"stream_event"` e o caso `"control_request", "control_response"`:

```swift
        case "assistant":
            return assistant(line)
        case "user":
            return user(line)
        case "result":
            return result(line)
```

- [ ] **Step 4: Acrescentar a extension durável no fim de `ClaudeEventMapper.swift`**

```swift
// MARK: - Durável

private extension ClaudeEventMapper {
    /// Uma entrada por bloco de conteúdo.
    ///
    /// A linha `assistant` é a forma CONSOLIDADA do mesmo turno que os
    /// `stream_event` entregaram delta a delta. É ela que vai para o
    /// transcript, e são eles que vão para a UI — as duas fontes carregam o
    /// mesmo texto (D1).
    func assistant(_ line: JSONValue) -> MappedOutput {
        let moment = timestamp(of: line)
        guard let blocks = line["message"]?["content"]?.arrayValue else {
            return MappedOutput(entries: [unrecognized("assistant", line, at: moment)])
        }
        return MappedOutput(entries: blocks.map { assistantBlock($0, at: moment) })
    }

    func assistantBlock(_ block: JSONValue, at moment: Date) -> TranscriptEntry {
        switch block["type"]?.stringValue {
        case "text":
            guard let text = block["text"]?.stringValue else { break }
            return TranscriptEntry(timestamp: moment, kind: .assistantText(text), raw: block)
        case "thinking":
            // A assinatura criptográfica do bloco fica no `raw` — ver D7.
            guard let text = block["thinking"]?.stringValue else { break }
            return TranscriptEntry(timestamp: moment, kind: .assistantThinking(text), raw: block)
        case "tool_use":
            guard let id = block["id"]?.stringValue,
                  let name = block["name"]?.stringValue else { break }
            let call = ToolCall(
                id: id,
                rawName: name,
                canonical: ClaudeToolVocabulary.canonical(for: name),
                input: block["input"] ?? .null
            )
            return TranscriptEntry(timestamp: moment, kind: .toolCall(call), raw: block)
        default:
            break
        }
        return unrecognizedBlock(block, at: moment)
    }

    /// Uma entrada por bloco `tool_result` — ou uma só, quando o conteúdo é a
    /// mensagem em texto.
    func user(_ line: JSONValue) -> MappedOutput {
        let moment = timestamp(of: line)
        guard let content = line["message"]?["content"] else {
            return MappedOutput(entries: [unrecognized("user", line, at: moment)])
        }
        // A forma em string é a que NÓS escrevemos no stdin; o CLI observado
        // não a ecoa de volta, então o corpus não a exercita. Mapeá-la mesmo
        // assim não inventa nada: `role: "user"` com conteúdo em texto é
        // exatamente o que `.userMessage` significa.
        if let text = content.stringValue {
            return MappedOutput(entries: [
                TranscriptEntry(timestamp: moment,
                                kind: .userMessage(text: text, attachments: []),
                                raw: line)
            ])
        }
        guard let blocks = content.arrayValue else {
            return MappedOutput(entries: [unrecognized("user", line, at: moment)])
        }
        return MappedOutput(entries: blocks.map { userBlock($0, at: moment) })
    }

    func userBlock(_ block: JSONValue, at moment: Date) -> TranscriptEntry {
        guard block["type"]?.stringValue == "tool_result",
              let callID = block["tool_use_id"]?.stringValue
        else { return unrecognizedBlock(block, at: moment) }

        let result = ToolResult(
            callID: callID,
            // Ausente significa "deu certo". O CLI só escreve a chave quando
            // a ferramenta falhou.
            isError: block["is_error"]?.boolValue ?? false,
            content: block["content"] ?? .null
        )
        return TranscriptEntry(timestamp: moment, kind: .toolResult(result), raw: block)
    }

    /// Como o turno fechou, com a contabilidade daquele turno.
    ///
    /// O campo `result` da linha NÃO vira `.assistantText`: ele repete a prosa
    /// do último bloco `text` da linha `assistant` anterior, e mapeá-lo
    /// duplicaria o último parágrafo de todo turno (D3). A linha inteira fica
    /// no `raw`, então nada se perde.
    func result(_ line: JSONValue) -> MappedOutput {
        let usage = line["usage"]
        let totals = UsageTotals(
            inputTokens: usage?["input_tokens"]?.intValue ?? 0,
            outputTokens: usage?["output_tokens"]?.intValue ?? 0,
            cacheReadTokens: usage?["cache_read_input_tokens"]?.intValue ?? 0,
            cacheCreationTokens: usage?["cache_creation_input_tokens"]?.intValue ?? 0,
            costUSD: line["total_cost_usd"]?.doubleValue ?? 0
        )
        let turn = TurnResult(
            usage: totals,
            stopReason: line["stop_reason"]?.stringValue,
            isError: line["is_error"]?.boolValue ?? false
        )
        return MappedOutput(entries: [
            TranscriptEntry(timestamp: timestamp(of: line), kind: .turnResult(turn), raw: line)
        ])
    }

    func unrecognizedBlock(_ block: JSONValue, at moment: Date) -> TranscriptEntry {
        unrecognized("content/" + (block["type"]?.stringValue ?? "?"), block, at: moment)
    }

    /// O `timestamp` da linha, quando ela traz um.
    ///
    /// Só `assistant` e `user` trazem; `system`, `result`, `stream_event` e
    /// `rate_limit_event` não trazem nenhum, e para essas vale o relógio
    /// injetado. Um carimbo que não analisa também cai no relógio, em vez de
    /// derrubar a entrada (spec §5.4).
    func timestamp(of line: JSONValue) -> Date {
        guard let text = line["timestamp"]?.stringValue else { return now() }
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return date
        }
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle()) {
            return date
        }
        return now()
    }
}
```

> A extension vai no MESMO arquivo, depois do tipo. `now` e
> `unrecognized(_:_:at:)` já são `internal` (Task 3), então ela os alcança sem
> mudar nada.

- [ ] **Step 5: Rodar e verificar que passa**

```bash
cd Packages/HarnessKit && swift test --filter ClaudeEventMapperTests
```
Esperado: PASSA (28 testes), sem warnings.

- [ ] **Step 6: Commit**

```bash
git add Packages/HarnessKit/Sources/ClaudeHarness/ClaudeEventMapper.swift \
        Packages/HarnessKit/Tests/ClaudeHarnessTests/ClaudeEventMapperTests.swift
git commit -m "feat(claude): caminho durável de assistant, user e result"
```

---

### Task 5: Linhas de sistema, limite de uso e as entradas de permissão

**Files:**
- Modify: `Packages/HarnessKit/Sources/ClaudeHarness/ClaudeEventMapper.swift` (dois ramos no `switch`, uma extension)
- Create: `Packages/HarnessKit/Sources/ClaudeHarness/ClaudeEventMapper+Permission.swift`
- Test: `Packages/HarnessKit/Tests/ClaudeHarnessTests/ClaudeEventMapperTests.swift` (acrescentar ao final)

**Interfaces:**
- Consumes: `unrecognized(_:_:at:)`, `timestamp(of:)`, `now` (Tasks 3 e 4);
  `PermissionRequest`, `PermissionDecision`, de `HarnessCore`.
- Produces:
  - Os ramos `"system"` e `"rate_limit_event"` no `switch` de `map(_:)`.
  - `public func entry(for request: PermissionRequest, raw: JSONValue) -> TranscriptEntry`
  - `public func entry(for decision: PermissionDecision, requestID: String, raw: JSONValue) -> TranscriptEntry`

**Por que as duas funções de permissão moram no mapeador.** Nove tipos de
entrada da spec §4.2, e dois deles — `permissionRequest` e
`permissionDecision` — não vêm do stdout de conversa: vêm do canal de
controle, que a Etapa 3 já construiu e que já entrega um `PermissionRequest`
neutro. Sem estas duas funções o transcript sairia incompleto justamente no
caminho que a spec §5.6 protege. Elas são o mesmo ofício do resto do arquivo —
cunhar uma `TranscriptEntry` com o carimbo certo e o `raw` intacto — e o
mapeador é quem tem o relógio injetado. São instâncias, não estáticas, por
isso.

**`system/permission_denied` é uma decisão, não um aviso.** O CLI só encaminha
`can_use_tool` ao cliente quando as regras avaliam para "ask" (ver as notas do
protocolo); `permission_denied` é o caso em que as regras negaram sozinhas.
Isso É uma `PermissionDecision.deny` — feita pelo harness, não pelo usuário — e
registrá-la como `.systemNotice` perderia a semântica de que aquela ferramenta
foi barrada. `interrupt: false` porque o turno observado seguiu: nas 6
negações do corpus, veio um `tool_result` com `is_error: true` logo depois e a
conversa continuou.

**A entrada de `permission_denied` e o `toolResult` que vem depois convivem.**
São dois fatos distintos e ambos verdadeiros: o harness negou, e a ferramenta
devolveu erro. Nenhum dos dois é derivado do outro, e a fidelidade da §4.2
exige os dois.

- [ ] **Step 1: Escrever o teste que falha**

Acrescentar ao final de `Tests/ClaudeHarnessTests/ClaudeEventMapperTests.swift`:

```swift
// MARK: - Linhas de sistema

@Test func systemInitAnnouncesTheModelAndAlsoLandsInTheTranscript() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"system","subtype":"init","model":"claude-opus-5",
     "session_id":"cf77236a-23fd-43ad-95ed-a5ea2792daba","cwd":"/tmp","tools":["Bash"]}
    """#))
    #expect(out.events == [.sessionInitialized(model: "claude-opus-5",
                                               harnessSessionID: "cf77236a-23fd-43ad-95ed-a5ea2792daba")])
    #expect(out.entries.count == 1)
    #expect(out.entries[0].kind == .systemNotice(subtype: "init", text: "claude-opus-5"))
    // D4: entrada derivada da linha carrega a linha inteira.
    #expect(out.entries[0].raw["cwd"]?.stringValue == "/tmp")
}

/// D2: 21 das 30 linhas `system` do corpus são progresso de exibição. Elas vão
/// para a UI e morrem ali — o transcript é registro semântico, não log de
/// exibição (spec §4.2).
@Test func statusAndThinkingTokensAreEphemeralOnly() throws {
    let status = makeMapper().map(try json(#"""
    {"type":"system","subtype":"status","status":"Analisando","session_id":"s"}
    """#))
    #expect(status.events == [.notice(subtype: "status", text: "Analisando")])
    #expect(status.entries.isEmpty)

    let thinking = makeMapper().map(try json(#"""
    {"type":"system","subtype":"thinking_tokens","estimated_tokens":1024,
     "estimated_tokens_delta":32,"session_id":"s"}
    """#))
    #expect(thinking.events == [.notice(subtype: "thinking_tokens", text: "1024")])
    #expect(thinking.entries.isEmpty)
}

@Test func permissionDeniedIsADecisionNotANotice() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"system","subtype":"permission_denied","tool_name":"Bash",
     "tool_use_id":"toolu_01MY","message":"Output redirection was blocked.","session_id":"s"}
    """#))
    #expect(out.events.isEmpty)
    #expect(out.entries.count == 1)
    #expect(out.entries[0].kind == .permissionDecision(
        requestID: "toolu_01MY",
        .deny(message: "Output redirection was blocked.", interrupt: false)))
}

@Test func aPermissionDeniedWithoutAToolUseIDIsPreservedNotGuessed() throws {
    let line = try json(#"{"type":"system","subtype":"permission_denied","message":"x"}"#)
    let entry = try #require(makeMapper().map(line).entries.first)
    #expect(entry.kind == .unrecognized(discriminator: "claude:system/permission_denied", payload: line))
}

@Test func anUnknownSystemSubtypeIsPreserved() throws {
    let line = try json(#"{"type":"system","subtype":"algo_novo","campo":1}"#)
    let entry = try #require(makeMapper().map(line).entries.first)
    #expect(entry.kind == .unrecognized(discriminator: "claude:system/algo_novo", payload: line))
}

@Test func aSystemLineWithoutASubtypeIsPreserved() throws {
    let line = try json(#"{"type":"system","campo":1}"#)
    let entry = try #require(makeMapper().map(line).entries.first)
    #expect(entry.kind == .unrecognized(discriminator: "claude:system", payload: line))
}

/// Durável: é o que explica um turno que parou.
@Test func aRateLimitEventLandsInTheTranscript() throws {
    let out = makeMapper().map(try json(#"""
    {"type":"rate_limit_event","rate_limit_info":{"status":"allowed","resetsAt":1789617600,
     "rateLimitType":"five_hour","isUsingOverage":false},"session_id":"s"}
    """#))
    #expect(out.events.isEmpty)
    #expect(out.entries.count == 1)
    #expect(out.entries[0].kind == .systemNotice(subtype: "rate_limit", text: "allowed"))
    #expect(out.entries[0].raw["rate_limit_info"]?["rateLimitType"]?.stringValue == "five_hour")
}

// MARK: - Entradas de permissão

@Test func aPermissionRequestBecomesAnEntryWithItsSuggestions() throws {
    let raw = try json(#"""
    {"type":"control_request","request_id":"req-1","request":{"subtype":"can_use_tool",
     "tool_name":"Write","tool_use_id":"toolu_9"}}
    """#)
    let request = PermissionRequest(
        id: "req-1",
        toolName: "Write",
        displayName: "Write",
        input: .object(["file_path": .string("/tmp/a.txt")]),
        toolUseID: "toolu_9",
        suggestions: [PermissionSuggestion(type: "addRules", mode: "acceptEdits")]
    )
    let entry = makeMapper().entry(for: request, raw: raw)
    #expect(entry.timestamp == fixedNow)
    #expect(entry.raw == raw)
    guard case .permissionRequest(let stored) = entry.kind else {
        Issue.record("esperava .permissionRequest"); return
    }
    #expect(stored == request)
    #expect(stored.suggestions.count == 1)
}

@Test func aPermissionDecisionBecomesAnEntryKeyedByTheRequestID() {
    let entry = makeMapper().entry(
        for: .allow(updatedInput: nil), requestID: "req-1", raw: .null)
    #expect(entry.kind == .permissionDecision(requestID: "req-1", .allow(updatedInput: nil)))
    #expect(entry.timestamp == fixedNow)
}
```

- [ ] **Step 2: Rodar e verificar que falha**

```bash
cd Packages/HarnessKit && swift test --filter ClaudeEventMapperTests
```
Esperado: FALHA — `value of type 'ClaudeEventMapper' has no member 'entry'`.

- [ ] **Step 3: Acrescentar os ramos ao `switch` de `map(_:)`**

Logo depois do caso `"result"`:

```swift
        case "system":
            return system(line)
        case "rate_limit_event":
            return rateLimit(line)
```

- [ ] **Step 4: Acrescentar a extension de sistema em `ClaudeEventMapper.swift`**

No fim da `private extension ClaudeEventMapper` que a Task 4 criou:

```swift
    /// As linhas `system`, separadas por subtipo em efêmeras e duráveis.
    ///
    /// Dos 30 `system` do corpus, 21 são `status` (rótulo de spinner) e
    /// `thinking_tokens` (estimativa corrente de tokens): progresso de
    /// exibição, não semântica da conversa. Vão para a UI e morrem ali — o
    /// transcript é registro semântico (spec §4.2), e um replay para outro
    /// harness não ganha nada com eles.
    func system(_ line: JSONValue) -> MappedOutput {
        guard let subtype = line["subtype"]?.stringValue else {
            return MappedOutput(entries: [unrecognized("system", line)])
        }
        switch subtype {
        case "init":
            let model = line["model"]?.stringValue ?? ""
            return MappedOutput(
                events: [.sessionInitialized(
                    model: model,
                    harnessSessionID: line["session_id"]?.stringValue ?? ""
                )],
                entries: [TranscriptEntry(
                    timestamp: now(),
                    kind: .systemNotice(subtype: "init", text: model),
                    raw: line
                )]
            )

        case "status":
            return MappedOutput(events: [
                .notice(subtype: subtype, text: line["status"]?.stringValue ?? "")
            ])

        case "thinking_tokens":
            return MappedOutput(events: [
                .notice(subtype: subtype,
                        text: line["estimated_tokens"]?.intValue.map { String($0) } ?? "")
            ])

        case "permission_denied":
            // As regras do harness negaram sozinhas — o `can_use_tool` só
            // chega ao cliente quando elas avaliam para "ask". Isso é uma
            // decisão de permissão de verdade, feita pelo harness. Registrar
            // como aviso perderia a semântica de que a ferramenta foi barrada.
            //
            // `interrupt: false` porque o turno observado segue: nas 6
            // negações do corpus veio um `tool_result` com `is_error: true`
            // logo depois e a conversa continuou.
            guard let toolUseID = line["tool_use_id"]?.stringValue else {
                return MappedOutput(entries: [unrecognized("system/" + subtype, line)])
            }
            return MappedOutput(entries: [TranscriptEntry(
                timestamp: now(),
                kind: .permissionDecision(
                    requestID: toolUseID,
                    .deny(message: line["message"]?.stringValue ?? "", interrupt: false)
                ),
                raw: line
            )])

        default:
            return MappedOutput(entries: [unrecognized("system/" + subtype, line)])
        }
    }

    /// Durável: é o que explica, meses depois, um turno que parou no meio.
    func rateLimit(_ line: JSONValue) -> MappedOutput {
        MappedOutput(entries: [TranscriptEntry(
            timestamp: now(),
            kind: .systemNotice(
                subtype: "rate_limit",
                text: line["rate_limit_info"]?["status"]?.stringValue ?? ""
            ),
            raw: line
        )])
    }
```

- [ ] **Step 5: Escrever `ClaudeEventMapper+Permission.swift`**

```swift
import Foundation
import HarnessCore

// As duas entradas da spec §4.2 que não vêm do stdout de conversa.
//
// O canal de controle (Etapa 3) já entrega um `PermissionRequest` neutro e a
// UI já devolve uma `PermissionDecision` neutra; o que falta é o passo de
// virar transcript, com o carimbo e o `raw` certos. É o mesmo ofício do resto
// do mapeador, e é aqui que mora o relógio injetado — por isso são métodos de
// instância.
//
// O `raw` chega por parâmetro em vez de ser reconstruído: só o chamador tem a
// linha original do fio, e a §4.2 exige um registro fiel, não uma
// reconstrução aproximada.
public extension ClaudeEventMapper {
    /// A entrada que registra que o harness pediu permissão.
    func entry(for request: PermissionRequest, raw: JSONValue) -> TranscriptEntry {
        TranscriptEntry(timestamp: now(), kind: .permissionRequest(request), raw: raw)
    }

    /// A entrada que registra o que se decidiu sobre um pedido.
    ///
    /// `requestID` é o `PermissionRequest.id` a que esta decisão responde — o
    /// par é o que permite ler o transcript e saber o que foi aprovado.
    func entry(for decision: PermissionDecision, requestID: String,
               raw: JSONValue) -> TranscriptEntry {
        TranscriptEntry(
            timestamp: now(),
            kind: .permissionDecision(requestID: requestID, decision),
            raw: raw
        )
    }
}
```

> Este arquivo é outro, e alcança `now` porque a Task 3 já o declarou
> `internal`. Se ele estiver `private`, corrija na Task 3 — não duplique o
> relógio aqui.

- [ ] **Step 6: Rodar e verificar que passa**

```bash
cd Packages/HarnessKit && swift test --filter ClaudeEventMapperTests
```
Esperado: PASSA (37 testes), sem warnings.

- [ ] **Step 7: Commit**

```bash
git add Packages/HarnessKit/Sources/ClaudeHarness/ClaudeEventMapper.swift \
        Packages/HarnessKit/Sources/ClaudeHarness/ClaudeEventMapper+Permission.swift \
        Packages/HarnessKit/Tests/ClaudeHarnessTests/ClaudeEventMapperTests.swift
git commit -m "feat(claude): linhas de sistema, limite de uso e entradas de permissão"
```

---

### Task 6: As quatro fixtures, de ponta a ponta

**Files:**
- Create: `Packages/HarnessKit/Tests/ClaudeHarnessTests/ClaudeEventMapperFixtureTests.swift`

**Interfaces:**
- Consumes: tudo das Tasks 1-5. Não cria nada novo.

Esta task não escreve código de produção. Ela existe porque o plano inteiro
depende de uma afirmação — "uma fonte por destino" — que só é verificável
contra o protocolo real, e o protocolo real está gravado em quatro arquivos
que custaram dinheiro para existir. **Nenhum teste aqui executa o `claude`.**

Os números abaixo foram medidos nas fixtures ao escrever este plano. Se algum
não bater, o desacordo é entre o mapeador e o corpus — investigue, não ajuste
o número.

| Fixture | linhas | entradas | eventos |
|---|---|---|---|
| `hello.ndjson` | 12 | 4 | 5 |
| `tool-use.ndjson` | 55 | 6 | 42 |
| `permission-request.ndjson` | 8 | 6 | 1 |
| `permission-denied.ndjson` | 289 | 27 | 220 |

- [ ] **Step 1: Escrever os testes**

Em `Tests/ClaudeHarnessTests/ClaudeEventMapperFixtureTests.swift`:

```swift
import Testing
import Foundation
import HarnessCore
@testable import ClaudeHarness

private let clock = Date(timeIntervalSince1970: 1_000_000)

private func mapFixture(_ name: String) throws -> MappedOutput {
    let url = try #require(Bundle.module.url(
        forResource: "Fixtures/\(name)", withExtension: "ndjson"))
    let mapper = ClaudeEventMapper(now: { clock })
    var all = MappedOutput.empty
    for line in try String(contentsOf: url, encoding: .utf8)
        .split(separator: "\n") where !line.isEmpty {
        let out = mapper.map(line: Data(line.utf8))
        all.events += out.events
        all.entries += out.entries
    }
    return all
}

private func kindName(_ kind: TranscriptEntry.Kind) -> String {
    switch kind {
    case .userMessage: return "userMessage"
    case .assistantText: return "assistantText"
    case .assistantThinking: return "assistantThinking"
    case .toolCall: return "toolCall"
    case .toolResult: return "toolResult"
    case .permissionRequest: return "permissionRequest"
    case .permissionDecision: return "permissionDecision"
    case .systemNotice: return "systemNotice"
    case .turnResult: return "turnResult"
    case .unrecognized(let discriminator, _): return "unrecognized(\(discriminator))"
    }
}

/// As contagens medidas. Um desacordo aqui é entre o mapeador e o protocolo
/// real — não ajuste o número sem olhar a fixture.
@Test(arguments: [
    ("hello", 4, 5),
    ("tool-use", 6, 42),
    ("permission-request", 6, 1),
    ("permission-denied", 27, 220),
])
func everyFixtureMapsToTheMeasuredCounts(
    fixture: (name: String, entries: Int, events: Int)
) throws {
    let out = try mapFixture(fixture.name)
    #expect(out.entries.count == fixture.entries)
    #expect(out.events.count == fixture.events)
}

/// **O teste que este plano existe para escrever.** 289 linhas, das quais 194
/// são deltas de token carregando o MESMO texto que as linhas `assistant`
/// consolidadas — e 27 entradas no transcript. Se as duas fontes alimentassem
/// o durável, este número estaria nas centenas e todo turno apareceria
/// repetido no store (spec §4.4).
@Test func theDeltaStreamNeverReachesTheTranscript() throws {
    let out = try mapFixture("permission-denied")
    #expect(out.entries.count == 27)
    #expect(out.events.count == 220)

    let texts = out.entries.compactMap { entry -> String? in
        guard case .assistantText(let text) = entry.kind else { return nil }
        return text
    }
    #expect(texts.count == 1, "um texto consolidado por turno, não um por delta")
}

/// A sequência conta a história: o assistente chama a ferramenta, o harness
/// nega, a ferramenta devolve erro, o assistente raciocina — seis vezes.
@Test func theOrderOfKindsPreservesTheStory() throws {
    let kinds = try mapFixture("permission-denied").entries.map { kindName($0.kind) }
    #expect(kinds == [
        "systemNotice", "systemNotice",
        "toolCall", "permissionDecision", "toolResult", "assistantThinking",
        "toolCall", "permissionDecision", "toolResult", "assistantThinking",
        "toolCall", "permissionDecision", "toolResult", "assistantThinking",
        "toolCall", "permissionDecision", "toolResult", "assistantThinking",
        "toolCall", "permissionDecision", "toolResult", "assistantThinking",
        "toolCall", "permissionDecision", "toolResult",
        "assistantText", "turnResult",
    ])
}

@Test(arguments: ["hello", "tool-use", "permission-request", "permission-denied"])
func theHappyPathFixturesShareTheSameSpine(name: String) throws {
    let kinds = try mapFixture(name).entries.map { kindName($0.kind) }
    #expect(kinds.first == "systemNotice", "toda sessão abre com um system/init")
    #expect(kinds.last == "turnResult", "e fecha com o result do turno")
}

/// Cobertura do protocolo observado: se o mapeador conhece tudo que este CLI
/// emite, nenhuma linha do corpus degrada. Uma `unrecognized` aqui é uma
/// forma que o plano não previu — e a mensagem diz qual.
@Test(arguments: ["hello", "tool-use", "permission-request", "permission-denied"])
func noFixtureLineDegrades(name: String) throws {
    for entry in try mapFixture(name).entries {
        if case .unrecognized(let discriminator, _) = entry.kind {
            Issue.record("\(name): forma não prevista \(discriminator)")
        }
    }
}

/// Fidelidade referencial (spec §4.2): todo resultado de ferramenta aponta
/// para uma chamada que está no mesmo transcript. Sem isso o replay entrega
/// ao próximo harness uma resposta para uma pergunta que ele nunca viu.
@Test(arguments: ["tool-use", "permission-request", "permission-denied"])
func everyToolResultPointsAtAToolCallInTheSameTranscript(name: String) throws {
    let entries = try mapFixture(name).entries
    let callIDs = Set(entries.compactMap { entry -> String? in
        guard case .toolCall(let call) = entry.kind else { return nil }
        return call.id
    })
    #expect(!callIDs.isEmpty)
    for entry in entries {
        guard case .toolResult(let result) = entry.kind else { continue }
        #expect(callIDs.contains(result.callID), "resultado órfão: \(result.callID)")
    }
}

/// E o mesmo para as decisões de permissão: o `requestID` de uma negação é o
/// `tool_use_id` da chamada que foi barrada.
@Test func everyDenialPointsAtTheCallItBlocked() throws {
    let entries = try mapFixture("permission-denied").entries
    let callIDs = Set(entries.compactMap { entry -> String? in
        guard case .toolCall(let call) = entry.kind else { return nil }
        return call.id
    })
    var decisions = 0
    for entry in entries {
        guard case .permissionDecision(let requestID, let decision) = entry.kind else { continue }
        decisions += 1
        #expect(callIDs.contains(requestID), "negação órfã: \(requestID)")
        guard case .deny = decision else { Issue.record("esperava .deny"); continue }
    }
    #expect(decisions == 6)
}

/// A saída do mapeador tem que ser gravável: a `.unrecognized` tem contrato de
/// idempotência e os `raw` são JSON arbitrário vindo do fio. Este teste leva o
/// corpus inteiro até o disco e de volta.
@Test func theMappedTranscriptSurvivesTheStore() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mapper-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let entries = try mapFixture("permission-denied").entries
    let segment = Segment(harness: .claudeCode, harnessSessionID: UUID(), model: "claude-opus-5")
    let session = Session(title: "corpus", workingDirectory: root, segments: [segment])

    let store = FileTranscriptStore(root: root)
    try await store.saveMetadata(session)
    for entry in entries {
        try await store.append(entry, to: segment.id, in: session.id)
    }

    let loaded = try await store.load(session.id)
    #expect(loaded.allEntries.count == entries.count)
    #expect(loaded.allEntries.map(\.kind) == entries.map(\.kind))
    #expect(loaded.allEntries.map(\.raw) == entries.map(\.raw))
    #expect(loaded.allEntries.map(\.id) == entries.map(\.id))

    // Os carimbos NÃO são comparados por igualdade, e a razão é um achado:
    // o store codifica datas com `.iso8601`, que não escreve fração de
    // segundo. As linhas `assistant` e `user` trazem milissegundos
    // ("…:59.447Z"), então um carimbo que vai ao disco volta truncado no
    // segundo. Não é erro de ordenação — a ordem do transcript é a ordem de
    // append no NDJSON, não a do carimbo —, mas é perda de fidelidade, e está
    // anotada como pendência ao fim deste plano.
    for (loadedEntry, original) in zip(loaded.allEntries, entries) {
        #expect(abs(loadedEntry.timestamp.timeIntervalSince(original.timestamp)) < 1)
    }
}
```

- [ ] **Step 2: Rodar**

```bash
cd Packages/HarnessKit && swift test --filter ClaudeEventMapperFixture
```
Esperado: PASSA. Se `everyFixtureMapsToTheMeasuredCounts` falhar, leia a
fixture antes de mexer no número.

- [ ] **Step 3: Rodar a suíte inteira**

```bash
cd Packages/HarnessKit && swift build 2>&1 | tail -5 && swift test 2>&1 | tail -20
```
Esperado: build limpo sem warnings; os 199 testes que já existiam mais os
novos, todos verdes.

- [ ] **Step 4: Commit**

```bash
git add Packages/HarnessKit/Tests/ClaudeHarnessTests/ClaudeEventMapperFixtureTests.swift
git commit -m "test(claude): mapeador verificado contra as quatro fixtures gravadas"
```

---

## O que este plano deliberadamente NÃO faz

Listado para que um revisor não o cobre como omissão, e para que a próxima
etapa saiba onde pegar.

- **Não acumula usage no `Segment`.** O mapeador reporta o usage POR TURNO na
  entrada `.turnResult`. Somar isso em `Segment.usage` é da camada de sessão
  (Etapa 5), que é quem sabe quando um segmento começa e termina.
- **Não liga o mapeador ao `ControlChannel` nem ao `ProcessTransport`.** O
  mapeador é uma função pura de uma linha; quem lê o transporte, roteia os
  quadros de controle e grava no store é a camada de sessão.
- **Não cria a `.userMessage` do turno que nós enviamos.** Quem envia é quem
  registra — e quem envia ainda não existe.
- **Não reabre o teto de 8 MiB por linha** do `ProcessTransport`. As notas do
  protocolo marcaram isso para "quando o mapper existir"; agora ele existe, e
  a conclusão é que o teto não muda nada aqui: uma linha acima do teto é
  terminal no transporte e nunca chega ao mapeador. Fica como pendência do
  transporte, onde sempre esteve.
- **Não conserta a truncagem de fração de segundo do store.** Descoberto ao
  escrever a Task 6: `FileTranscriptStore` codifica datas com `.iso8601`, que
  não escreve milissegundos, enquanto as linhas `assistant` e `user` trazem
  milissegundos. Um carimbo que vai ao disco volta truncado no segundo. Não
  afeta a ordem do transcript (que é a ordem de append no NDJSON) nem nenhum
  teste existente, mas é perda de fidelidade contra a §4.2. Mudar a estratégia
  do store é mudança de formato de arquivo e pertence a um plano próprio;
  registre em `docs/superpowers/notes-2026-09-17-pendencias.md` ao fim da
  etapa.
- **Não resolve o buraco de tolerância do interior dos casos conhecidos**
  (`docs/superpowers/notes-2026-09-17-pendencias.md`). O mapeador só produz
  formas que esta versão sabe escrever, então não o agrava; o buraco continua
  do lado do leitor.
