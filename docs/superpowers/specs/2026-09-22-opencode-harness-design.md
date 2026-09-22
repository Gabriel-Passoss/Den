# OpenCode como segundo harness — cobrando o cheque da §4.1

**Data:** 2026-09-22
**Status:** Entregas 1 e 2 construídas e verificadas
**Spec fundador:** `docs/superpowers/specs/2026-09-16-devspace-fundacao-design.md`

## 1. Contexto e objetivo

A fundação declarou, na §9, que o segundo adaptador é o teste de verdade:

> O adaptador do Codex é o que vai provar se a abstração da seção 4.1 é real,
> e ele vem depois de a primeira estar de pé.

A primeira está de pé. Este documento traz o segundo adaptador — OpenCode no
lugar do Codex, porque é o CLI que o usuário tem instalado e quer usar — e,
no caminho, **implementa pela primeira vez os protocolos `Harness` e
`HarnessSession` que a §4.1 esboçou e ninguém construiu.**

O objetivo não é "somar um arquivo". É abrir a costura que hoje não existe:
`CockpitModel` guarda `private var session: ClaudeSession?` e dá `switch` em
`ClaudeSession.Update`; `ChatView` desenha `CockpitModel.modelChoices` com
Fable/Opus/Sonnet/Haiku fixos no código. O `HarnessCore` é neutro, mas a
camada de app fura direto para o `ClaudeHarness`. Enquanto isso for verdade,
a §2 ("orquestrador de harnesses, nunca um harness") é letra morta acima do
pacote.

## 2. O que foi verificado empiricamente

A §11 do spec fundador registrou como questão em aberto que o shape concreto
do protocolo de controle do Claude Code não havia sido verificado. Este
design não repete o erro: **todo quadro abaixo foi capturado de um
`opencode acp` real**, versão 1.18.31, em quatro sondagens gravadas.

### 2.1 A escolha do transporte

O OpenCode oferece três portas: `opencode serve` (HTTP + SSE),
`opencode run --format json` (turno único, sem interação) e `opencode acp`
(Agent Client Protocol: JSON-RPC 2.0 delimitado por linha, em stdio).

**Decisão: ACP.** É a única das três que é interativa, bidirecional e
delimitada por linha — ou seja, a única que **reaproveita `ProcessTransport`
e `NDJSONFramer` sem uma linha de alteração**. `serve` exigiria um cliente
HTTP e um parser de SSE escritos do zero, violando "zero dependências" ou
inflando o núcleo; `run` não tem canal de permissão nem interrupção.

### 2.2 Quadros capturados

| Método / notificação | Direção | Conteúdo confirmado |
|---|---|---|
| `initialize` | app → CLI | responde `protocolVersion: 1`, `agentInfo`, `authMethods` |
| ↳ `agentCapabilities` | CLI → app | `loadSession: true`, `sessionCapabilities: {close, fork, list, resume}`, `promptCapabilities: {image: true, embeddedContext: true}` |
| `session/new` | app → CLI | responde `sessionId` (`ses_…`) + `configOptions` |
| `session/load` | app → CLI | **reproduz o histórico inteiro** como notificações `session/update`, depois responde `configOptions` |
| `session/list` | app → CLI | `[{sessionId, cwd, title, updatedAt}]` |
| `session/prompt` | app → CLI | responde `{stopReason, usage: {inputTokens, outputTokens, cachedReadTokens, totalTokens}}` |
| `session/set_config_option` | app → CLI | parâmetro é **`configId`** (não `optionId`); troca `model` e `mode` em sessão viva |
| `session/cancel` | app → CLI | **é notificação, não request** (sem `id`); confirmado → `stopReason: "cancelled"` |
| `session/request_permission` | CLI → app | `{toolCall, options: [{optionId, kind, name}]}` |
| `session/update` | CLI → app | ver 2.3 |

### 2.3 Variantes de `session/update` observadas

| `sessionUpdate` | Carga | Destino no domínio |
|---|---|---|
| `agent_message_chunk` | `{messageId, content: {type: "text", text}}` | `.textDelta` → consolida em `.assistantText` |
| `agent_thought_chunk` | idem | `.thinkingDelta` → `.assistantThinking` |
| `user_message_chunk` | idem (só no replay do `session/load`) | `.userMessage` |
| `tool_call` | `{toolCallId, title, kind, status, locations, rawInput}` | `.toolCall(ToolCall)` |
| `tool_call_update` | idem + `content`, `rawOutput`, `status` | `.toolResult` quando `status` for terminal |
| `usage_update` | `{used, size, cost: {amount, currency}}` | `UsageTotals` do segmento |
| `available_commands_update` | lista de comandos/skills | ignorado (ruído de inicialização) |

### 2.4 Opções de permissão observadas

```
{ "optionId": "once",   "kind": "allow_once",   "name": "Allow once" }
{ "optionId": "always", "kind": "allow_always", "name": "Always allow" }
{ "optionId": "reject", "kind": "reject_once",  "name": "Reject" }
```

O OpenCode só encaminha o pedido quando a configuração dele avalia para
`ask` — exatamente a mesma ressalva que o `harness-probe` já documenta para o
Claude Code. Uma sondagem só viu permissão depois de escrever
`{"permission": {"bash": "ask"}}` no `opencode.json` do diretório.

### 2.5 Capacidades medidas, não supostas

| Capacidade | Claude Code | OpenCode | Evidência |
|---|---|---|---|
| `routesPermissionRequests` | `true` | `true` | 2.4 |
| `canInterrupt` | `true` | `true` | `session/cancel` → `stopReason: "cancelled"` |
| `canSetPermissionMode` | `true` | `true` | `set_config_option` `configId: "mode"` (`build`/`plan`) |
| `canSetModelInSession` | **`false`** | **`true`** | `set_config_option` `configId: "model"` |
| `canResumeSession` | `true` | `true` | `session/load` reproduz o histórico |
| `canForkSession` | `true` | `true` | `sessionCapabilities.fork` |

O OpenCode supera o Claude Code em `canSetModelInSession`. Isso é a melhor
notícia deste design: prova que `HarnessCapabilities` não é decoração. A UI
vai relançar a sessão para trocar modelo no Claude e trocar a quente no
OpenCode, lendo a capacidade em vez de assumir.

## 3. Emendas ao spec fundador

Implementar a §4.1 revelou onde o esboço de 2026-09-16 não sobrevive ao
contato com o segundo harness. Cada emenda abaixo é deliberada.

| § | Esboço original | Emenda | Razão |
|---|---|---|---|
| 4.2 | `Segment.harnessSessionID: UUID` | `String` | IDs do OpenCode são `ses_f36f01b7dffeoyVh8oyerb5GJG`, não UUIDs. **Sem migração:** verificado contra `~/Library/Application Support/DevSpace/sessions` que o campo já é string JSON; trocar o tipo Swift lê o histórico existente intacto. `ClaudeLaunch` reconverte com `UUID(uuidString:)`. |
| 4.1 | propriedade `HarnessSession.events: AsyncStream<SessionEvent>` | `start(_:)` **devolve** `AsyncStream<SessionUpdate>` | Dois desvios do esboço, ambos já presentes no `ClaudeSession` de hoje. O fluxo nasce do `start` porque antes dele não há o que observar. E `SessionEvent` é estreito demais: o `Update` atual carrega evento efêmero, entrada durável, permissão, controle não reconhecido e fim — cinco coisas que um `AsyncStream<SessionEvent>` só expressaria com um segundo canal. |
| 4.1 | `SessionSpec.resuming: UUID?` | `SessionStart` (o enum que já existe em `ClaudeLaunch`) | O enum `.fresh/.resume/.fork` já é mais honesto que o campo opcional, e sobe para o núcleo. |
| 4.1 | `PermissionDecision { allow, deny }` | ganha `.option(id: String)` | O OpenCode oferece três saídas nomeadas por ele; achatar para dois perde "sempre permitir". |
| 3 (tabela) | Handoff: "briefing **ou** replay, à escolha do usuário" | replay com briefing no estouro de orçamento | Perguntar a cada troca é atrito; o replay é fiel quando cabe, e o briefing existe como degradação automática. Os dois casos de `Handoff` continuam em uso. |

Nenhuma emenda toca a §2, a §5.4 (tolerância por construção) ou a §7.1 (veto
de palavras no núcleo). Essas três continuam invioláveis.

## 4. Arquitetura

### 4.1 A costura, finalmente construída

Sobe para `HarnessCore`, cumprindo a regra da §7.1 ("se um tipo não menciona
Claude e um segundo adaptador precisaria dele, ele é de `HarnessCore`"):

```swift
public enum SessionUpdate: Sendable {
    case event(SessionEvent)
    case entry(TranscriptEntry)
    case permission(PermissionRequest)
    case unrecognizedControl(UnrecognizedControl)
    case ended(error: String?)
}

public protocol Harness: Sendable {
    var id: HarnessID { get }
    var displayName: String { get }
    func discover() async throws -> HarnessInstallation
    func capabilities(for installation: HarnessInstallation) -> HarnessCapabilities
    func knobs(for installation: HarnessInstallation,
               workingDirectory: URL) -> [HarnessKnob]
    func makeSession(installation: HarnessInstallation,
                     workingDirectory: URL,
                     settings: [String: String]) -> any HarnessSession
}

public protocol HarnessSession: Actor {
    func start(_ start: SessionStart) async throws -> AsyncStream<SessionUpdate>
    func send(_ turn: UserTurn) async throws
    func resolve(_ requestID: String, _ decision: PermissionDecision) async throws
    func interrupt() async throws
    func apply(knob id: String, value: String?) async throws
    func stop() async
}
```

`knobs` recebe o diretório de trabalho porque é de lá que o adaptador do
Claude lê os padrões detectados (`ClaudeSettings` varre
`.claude/settings.local.json`, `.claude/settings.json` e o do `$HOME`). Sem o
diretório, `detectedMode` e `detectedEffort` não teriam de onde vir.

**O que sobe para `HarnessCore`:** `MediaAttachment`, `UnrecognizedControl` e
`SessionStart` migram de `ClaudeHarness` — não mencionam o CLI de origem e o
segundo adaptador precisa dos três, então a §7.1 os reclama. `UserTurn` é
**criado** aqui (a §4.1 o esboçou; ninguém o construiu — hoje a assinatura é
`send(_ text: String, attachments: [MediaAttachment])`).

**O que fica onde está:** `EffortLevel` **não** sobe. O teste da §7.1 tem duas
metades, e ele só passa na primeira: não menciona Claude, mas o segundo
adaptador não precisa dele — `low…max` é o vocabulário do `--effort` do
Claude Code, e o OpenCode não tem esforço nenhum. Ele permanece em
`ClaudeHarness`, e quem o consumia acima do pacote passa a falar valor de
botão (§4.3).

`ClaudeSession` passa a cumprir `HarnessSession` — a mudança é de assinatura,
não de comportamento, porque o `Update` dele já é o `SessionUpdate`.

### 4.2 Onde os dois adaptadores se encontram

Se o `CockpitModel` larga o `import ClaudeHarness`, alguém precisa continuar
conhecendo os adaptadores concretos. Esse alguém é um registro no app, e ele
é o **único** lugar acima do pacote que importa os dois módulos:

```swift
// DevSpace/HarnessRegistry.swift
@MainActor enum HarnessRegistry {
    static let all: [any Harness] = [ClaudeCodeHarness(), OpenCodeHarness()]
    static func harness(for id: HarnessID) -> (any Harness)?
}
```

`WorkspaceModel` (que hoje tem `let defaultHarness: HarnessID = .claudeCode`)
e `HarnessBadge` (que hoje dá `switch` em `.claudeCode`) passam a perguntar ao
registro em vez de conhecer um CLI por nome. É o que faz o menu de "nova
sessão" e o selo do cockpit ganharem o OpenCode sem `if` espalhado.

### 4.3 Os botões viram dados

O Claude Code tem apelidos fixos (Fable/Opus/Sonnet/Haiku) e esforço
(low…max). O OpenCode **descobre** a lista de modelos em runtime e tem
`build`/`plan` no lugar de esforço. Ou a `ChatView` enche de
`if harness == …`, ou os botões viram dados:

```swift
public struct HarnessKnob: Identifiable, Sendable, Equatable {
    public enum Category: String, Sendable { case model, effort, mode }
    public struct Option: Sendable, Equatable {
        public let value: String
        public let label: String
    }
    public let id: String            // "model", "effort", "mode"
    public let category: Category
    public let name: String          // rótulo da UI, já capitalizado
    public var currentValue: String?
    public var options: [Option]
}
```

O adaptador do Claude devolve botões estáticos; o do OpenCode devolve o que
os `configOptions` do ACP responderam, e os atualiza quando
`set_config_option` retorna a lista nova. A `ChatView` desenha um menu por
botão, e some com `modelChoices`/`effortChoices` fixos. O terceiro harness
não vai exigir mudança de UI.

**Consequência no `CockpitModel`:** os três campos tipados
(`preferredModel: String?`, `preferredEffort: EffortLevel?`,
`preferredMode: PermissionMode?`) viram um `settings: [String: String]`
indexado por id de botão, e o par `detectedMode`/`detectedEffort` sai de cena
— o `currentValue` de cada `HarnessKnob` já carrega o padrão que o adaptador
detectou. É isso que permite ao `CockpitModel` largar o `import ClaudeHarness`,
que é o objetivo da etapa 2 da Entrega 1. A persistência em
`UserDefaults.DevSpace.sessionPreferences` já grava `[String: [String: String]]`
por sessão, então o formato no disco não muda de forma.

### 4.4 Permissão com as opções do harness

```swift
public struct PermissionOption: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable {
        case allowOnce, allowAlways, rejectOnce, rejectAlways
    }
    public let id: String
    public let kind: Kind
    public let label: String
}
```

`PermissionRequest` ganha `options: [PermissionOption]`. O `ControlChannel` do
Claude sintetiza duas (permitir/negar) e a tela dele não muda; o OpenCode
repassa as três de 2.4. O card desenha um botão por opção.

`PermissionDecision` ganha `.option(id:)`. É `Codable` e é persistido dentro
de `TranscriptEntry.Kind.permissionDecision`; acrescentar um caso não quebra
a leitura do que já está gravado.

### 4.5 O alvo `OpenCodeHarness`

Espelha a forma do `ClaudeHarness`, peça por peça — a simetria é intencional
e é ela que prova a abstração:

| Arquivo | Papel | Análogo |
|---|---|---|
| `HarnessID+OpenCode.swift` | `HarnessID(rawValue: "opencode")` | `HarnessID+ClaudeCode.swift` |
| `OpenCodeDiscovery.swift` | `$SHELL -l -c 'command -v opencode'` + fallbacks; versão é `1.18.31` pelado, sem prefixo | `ClaudeDiscovery.swift` |
| `ACPFrames.swift` | envelopes JSON-RPC 2.0: request, response, erro e **notificação** | `ControlFrames.swift` |
| `ACPChannel.swift` | correlação por `id`, requests de entrada, notificações de saída | `ControlChannel.swift` |
| `OpenCodeEventMapper.swift` | `session/update` → `SessionEvent`/`TranscriptEntry` | `ClaudeEventMapper.swift` |
| `OpenCodeSession.swift` | ator que cumpre `HarnessSession` | `ClaudeSession.swift` |
| `OpenCodeToolVocabulary.swift` | `kind` do ACP → `CanonicalTool` | `ClaudeToolVocabulary.swift` |

Os caminhos de fallback da descoberta, em ordem: `/opt/homebrew/bin/opencode`,
`/usr/local/bin/opencode`, `~/.opencode/bin/opencode`, `~/.local/bin/opencode`.

O vocabulário é quase identidade, porque o ACP já canonizou: `read` → `.read`,
`edit` → `.edit`, `execute` → `.execute`, `search` → `.search`,
`fetch` → `.fetch`, `delete`/`move` → `.write`; qualquer outro (`think`,
`other`) → `nil`, preservado no `raw` pela §5.4.

### 4.6 Ciclo do ACP

```
initialize ──► session/new  (fresh)
           └─► session/load (resume: reproduz histórico como session/update)
                     │
                     ▼
              session/prompt ──► turno roda, chegam session/update
                     │           e session/request_permission
                     ▼
              {stopReason, usage} ──► TranscriptEntry.turnResult
```

`stopReason: "cancelled"` marca o turno como interrompido no transcript — a
§5.5 exige isso, sem o qual o replay reconstrói uma conversa que não houve.

## 5. Handoff: a troca no meio da sessão

A §4.2 já modelou isto; falta executá-lo. Limite duro medido: **nem o Claude
Code nem o OpenCode aceitam injetar turnos de assistente numa sessão nova.**
Ambos só recebem conteúdo de usuário. Então "mesmo contexto" significa
materializar o transcript em texto e entregá-lo como a primeira mensagem.

`CockpitModel.segmentID` é `let` hoje e vira `var currentSegmentID`;
`domainSession` passa a carregar **todos** os segmentos, não só o último.

`switchHarness(to:)`:

1. para a sessão atual (`stop()`);
2. monta a semente em Markdown a partir de `session.allEntries` — turnos de
   usuário e assistente na íntegra, chamadas de ferramenta em uma linha cada;
3. mede contra um orçamento de **60 000 caracteres**. Cabendo →
   `seededBy: .replay(throughEntry: <id da última entrada>)`. Estourando →
   pede um resumo de handoff ao harness que está saindo, antes de derrubá-lo,
   e usa `seededBy: .briefing(texto)`;
4. abre `Segment(harness: novo, seededBy: …)` e **grava o metadata antes do
   primeiro append** — `FileTranscriptStore.append` exige que o segmento já
   conste do `session.json`, e violar essa ordem lança `segmentNotFound`;
5. sobe o adaptador novo e manda a semente como primeira mensagem, desenhada
   na tela como aviso ("Contexto transferido para o OpenCode"), nunca como
   balão de usuário — a semente é procedimento, não algo que o usuário disse.

O orçamento de 60 000 caracteres é deliberadamente conservador (~15 000
tokens): serve para caber com folga em qualquer janela de destino, não para
espremer o máximo. O gatilho para revisitá-lo é o briefing disparar em
sessões que obviamente caberiam.

## 6. Superfície de UI

| Lugar | Mudança |
|---|---|
| Nova sessão | Botão vira menu: clique usa o harness padrão, chevron escolhe. `WorkspaceModel.defaultHarness` deixa de ser `let` e vira preferência persistida. |
| Cockpit | Selo do harness ao lado do selo de modelo, abrindo o menu de troca. |
| Card de permissão | Um botão por `PermissionOption`, no lugar de Negar/Permitir fixos. |
| Menus de modelo/esforço | Passam a ser desenhados a partir de `[HarnessKnob]`. |
| `SessionRow` | Já desenha `HarnessBadge` para `summary.harnesses`; ganha o caso do OpenCode. |

**Pendência declarada:** não temos o logo do OpenCode. O `HarnessBadge` já cai
num monograma quando falta asset, então o primeiro corte mostra "O" e o
`HarnessOpenCode.imageset` entra quando o arquivo existir. Isso não bloqueia
nada.

Rótulos seguem a convenção da casa: primeira palavra maiúscula, resto
minúsculo.

## 7. Estratégia de teste

Segue a §6 do spec fundador sem desvio. **Nenhum teste executa o `opencode`.**
As quatro sondagens desta investigação já gravaram os quadros reais, e eles
viram fixtures em `Tests/OpenCodeHarnessTests/Fixtures/`, estritamente de
leitura.

`harness-probe` ganha `--harness <claude-code|opencode>` em `discover`,
`record` e `permission`. É como fixtures nascem legitimamente neste projeto
(§6), e mantém o probe útil para o adaptador novo em vez de fossilizá-lo no
primeiro.

| Suíte | Contra o quê |
|---|---|
| `OpenCodeEventMapperTests` | fixtures NDJSON, espelhando `ClaudeEventMapperFixtureTests` |
| `ACPFramesTests` | encode/decode dos envelopes; **notificação não carrega `id`** |
| `ACPChannelTests` | correlação por id, timeout, request de entrada, canal fechado |
| `OpenCodeDiscoveryTests` | `CommandRunner` falso, espelhando `ClaudeDiscoveryTests` |
| `HandoffSeedTests` | transcript → Markdown; orçamento; queda para briefing |
| `HarnessCoreTests` (adição) | round-trip de sessão multi-segmento com `harnessSessionID` não-UUID |

Restrições da casa que continuam valendo: Swift Testing (`@Test`/`#expect`),
nunca XCTest; zero dependências externas; nenhuma asserção de tempo de
relógio; fixtures existentes são intocáveis.

## 8. Ordem de construção

Duas entregas. A primeira já é utilizável sozinha — o que respeita a lição
registrada de que fundação demais sem tela custa o ritmo do projeto.

### Entrega 1 — a costura e o OpenCode de pé

| # | Etapa | Entregável verificável |
|---|---|---|
| 1 | `Harness`/`HarnessSession` em `HarnessCore`; tipos neutros migram | pacote compila; suítes existentes passam sem alteração de comportamento |
| 2 | `ClaudeSession` cumpre `HarnessSession`; `CockpitModel` fala só o protocolo | app roda idêntico ao de hoje, sem `import ClaudeHarness` no `CockpitModel` |
| 3 | `ACPFrames` + `ACPChannel` | `ACPChannelTests` passa contra binário falso |
| 4 | `OpenCodeDiscovery` + `OpenCodeEventMapper` | `harness-probe discover --harness opencode` imprime caminho e versão; mapper passa contra fixtures |
| 5 | `OpenCodeSession` + `HarnessKnob` + opções de permissão | **sessão OpenCode real no DevSpace: streaming, ferramenta, permissão de três botões, interrupção** |

### Entrega 2 — a troca no meio da sessão

| # | Etapa | Entregável verificável |
|---|---|---|
| 6 | `CockpitModel` multi-segmento | sessão com dois segmentos sobrevive a fechar e reabrir o app |
| 7 | Semente de handoff + orçamento + queda para briefing | `HandoffSeedTests` passa |
| 8 | Seletor de troca no cockpit | trocar de Claude para OpenCode no meio da conversa, mantendo o contexto |

## 9. Fora de escopo

`opencode serve` e seu cliente HTTP/SSE; MCP; o reaper de sessão quente da
§5.1 (que segue não implementado e não é deste trabalho); busca; UI de custo;
qualquer refatoração que não esteja no caminho destas oito etapas.

## 10. Riscos

| Risco | Severidade | Mitigação |
|---|---|---|
| ACP é jovem e pode mudar entre versões do OpenCode | Alta | §5.4 vale igual: tipo desconhecido nunca é erro, `raw` guarda tudo, fixtures detectam regressão |
| `CockpitModel` multi-segmento quebra sessões gravadas | Média | Entrega 2 é separada e tem round-trip de persistência como critério; o campo `harnessSessionID` foi verificado compatível contra arquivos reais |
| A abstração da §4.1 não aguentar o segundo harness | Média | É exatamente o que este trabalho mede; onde não aguentou, a §3 registra a emenda em vez de disfarçar |
| Fidelidade do replay entre harnesses | Média | Transcript semântico + vocabulário canônico (§4.5); briefing como degradação automática |
| Logo do OpenCode ausente | Baixa | Monograma já é o fallback do `HarnessBadge`; não bloqueia |

## 11. Como ficou construído

Registrado depois da Entrega 1, porque o contato com o CLI corrigiu o desenho
em cinco pontos. A §3 emendou o spec fundador; esta seção emenda **este**
documento.

| Ponto | Desenho | Como ficou | Razão |
|---|---|---|---|
| `SessionStart.fresh` | herdava `sessionID: UUID` | não carrega nada | O DevSpace gera o id do Claude (`--session-id`), mas quem gera o do OpenCode é o CLI (`session/new`). O caso neutro honesto é vazio: cada adaptador resolve a identidade e a devolve pelo `sessionInitialized`, que já era `String`. O enum com UUIDs sobreviveu como `ClaudeSessionStart`, dentro do `ClaudeHarness`, o que manteve as 14 asserções de argv do `ClaudeLaunchTests` intactas. |
| Botões | só `Harness.knobs(for:workingDirectory:)` | mais `HarnessSession.knobs()` | Os do Claude são estáticos e existem antes da sessão; os do OpenCode **nascem** do `session/new` e mudam a cada `set_config_option`. Uma função só não expressa as duas coisas. |
| Título da sessão | não previsto | `Harness.titleArguments(for:)`, padrão `nil` | A geração de título rodava `claude -p … --model haiku` direto no `CockpitModel` — específica do Claude, e teria vazado o import de volta. Virou uma pergunta ao adaptador. **Lacuna conhecida:** o OpenCode devolve `nil`, então sessões dele ficam com o título curto do primeiro pedido, sem a versão gerada. |
| Anúncio de ferramenta | imediato, no quadro `tool_call` | adiado até o `status` sair de `pending` | Descoberto pela fixture: no `pending` o `rawInput` traz só o `cwd` — **o comando ainda não existe**. Anunciar ali gravaria uma ferramenta sem argumento. E o quadro terminal vem com `rawInput: null`, então o mapper retém o valor mais rico em vez de aceitar o último. |
| Opções de permissão | campo novo no `PermissionRequest` | idem, com decode tolerante | O `PermissionRequest` é persistido. Um `init(from:)` tolerante lê os transcripts anteriores ao campo, e dois testes novos fixam isso em vez de deixá-lo implícito: o dourado do formato provou que só o **encode** mudou. |
| Briefing no estouro (§5) | **pedir um resumo ao harness que está saindo** | truncagem determinística dos turnos mais recentes, com marcador de omissão | Desvio consciente. Pedir o resumo exige um turno completo de ida e volta no harness que está sendo derrubado — subscrever o stream, esperar o `turnResult`, colher o texto — com o risco de travar a troca se ele não responder. A truncagem cabe sempre, é instantânea e é testável sem gastar token. O caso `.briefing` do enum continua sendo o registro de proveniência correto: o que foi semeado é um documento condensado, não o replay completo. **Trocar isto por um resumo de modelo continua valendo**, se na prática a truncagem perder contexto que importa. |
| Marca da troca | aviso só na tela | entrada `systemNotice(subtype: "harness_switch")` no transcript, **não desenhada** | O transcript guarda onde a conversa mudou de harness, mas a tela não fala: ver a troca anunciada não ajuda quem acabou de fazê-la. O subtype entrou em `CockpitModel.silentNotices`, junto de `init` e `rate_limit`, o que também cala os avisos já gravados antes desta decisão. |
| Entrega da semente (§5.4) | turno próprio, logo depois da troca | **prefixo da primeira mensagem** que o usuário escrever no segmento novo | Como turno próprio ela fazia o harness novo responder a uma conversa que o usuário não acabou de escrever — uma resposta que ninguém pediu, aparecendo sozinha no chat. Colada ao primeiro pedido (`HandoffSeed.message(seed:request:)`, com `---` e `**Agora, o pedido:**` separando histórico de pedido), a troca fica instantânea e muda, pela ordem: nada aparece na tela, nenhum turno é gasto, e trocar sem escrever nada não custa token. Se o app fechar antes do primeiro pedido, a restauração vê `seededBy` num segmento sem entradas e repõe a semente pendente. |
| Categoria dos botões do OpenCode | `model` ou `mode` | mais `thought_level` → `.effort` | Medido no CLI depois: além de `model` e `mode`, existe um `effort` classificado como `thought_level` que **aparece e some conforme o modelo** (GPT-5.x tem, Big Pickle não). Caindo no balde do modo, ele era desenhado do lado errado do campo de texto. Um balde desconhecido agora cai em `.effort`, que é o lado onde cabe um botão a mais. |
| Rótulos do OpenCode | o que o CLI mandar, capitalizado | tradução por par botão/valor | O CLI manda `build`/`plan` e `none…xhigh`/`default` em inglês. A tradução é por par porque `default` quer dizer coisas diferentes em botões diferentes; o que não estiver na tabela ainda cai no nome que o CLI deu. |
| Lista de modelos | `[(value, label)]` plana | `Option.group` + `HarnessKnob.groupedOptions` | São 23 modelos num campo só, no formato `"OpenAI/GPT-5.5"`. O provedor virou cabeçalho de seção do menu e o rótulo ficou com o nome do modelo sozinho — senão o botão fechado repete o provedor a cada troca. O Claude não preenche `group` e segue com lista plana. |

### 11.1 Verificação

- 48 testes novos no `OpenCodeHarnessTests`; nenhum dos 276 existentes quebrou.
- O veto da §7.1 continua verde — ele é testado por
  `harnessCoreNeverNamesASpecificHarness`.
- Ponta a ponta contra o `opencode` real (fora da suíte, como manda a §6):
  descoberta, botões, id `ses_…`, pensamento, ferramenta com `canonical`
  correto, permissão de três opções, resultado, streaming, `turnResult` com
  uso, encerramento limpo.
- O app compila, sobe e se mantém.

Da Entrega 2:

- 11 testes novos no núcleo — a semente (ordem das vozes, ferramentas sem
  saída, raciocínio descartado, orçamento, estouro) e a persistência
  multi-segmento com `harnessSessionID` não-UUID, incluindo a recusa do store
  que obriga a gravar o metadata antes da semente.
- Handoff real contra o `opencode`: semeado com uma conversa anterior, ele
  **não respondeu à conversa antiga** (o preâmbulo funcionou) e depois
  respondeu corretamente uma pergunta que só o contexto transferido explica.

**Não verificado:** os menus da UI foram conferidos só pelo compilador — o
seletor de harness no cabeçalho, o de "Nova sessão com" na sidebar e o card de
permissão de três botões. O `osascript` não tem acesso assistivo nesta máquina,
então a hierarquia de acessibilidade não pôde ser lida e nenhum clique real foi
dado. O app compila, sobe e se mantém.
