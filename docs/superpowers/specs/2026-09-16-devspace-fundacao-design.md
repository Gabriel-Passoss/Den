# DevSpace — Fundação: orquestrador de harnesses de IA

**Data:** 2026-09-16
**Status:** Aprovado, pronto para plano de implementação

## 1. Contexto e objetivo

DevSpace é uma aplicação macOS para gerenciar múltiplas sessões de agentes de
codificação. A primeira integração é o Claude Code instalado na máquina do
usuário, reaproveitando a autenticação que ele já tem.

O objetivo desta fundação é levantar o núcleo que torna tudo o resto possível:
falar com um harness, normalizar o que sai dele, e persistir isso num formato
que sobreviva à troca de harness.

## 2. Princípio norteador

**DevSpace é um orquestrador de harnesses, nunca um harness.** Não
implementamos loop de agente, gestão de contexto ou execução de ferramenta.
Delegamos isso a CLIs existentes (Claude Code hoje; Codex, OpenCode e outros
depois) e nos concentramos em orquestrar, normalizar e persistir.

Toda decisão neste documento é subordinada a esse princípio. Quando houver
conflito entre conveniência imediata e manter a abstração de harness honesta,
a abstração ganha.

## 3. Decisões fixadas

| Decisão | Valor | Razão |
|---|---|---|
| Modo de uso | Cockpit interativo | Streaming, aprovação de ferramenta e interrupção são o núcleo do produto |
| Transporte | Swift nativo | Abstração de harness uniforme; nenhum runtime embutido; Codex e OpenCode não teriam SDK TypeScript |
| Histórico | DevSpace é dono, formato normalizado próprio | Pré-requisito para troca de harness mantendo a sessão |
| Handoff | Briefing **ou** replay, à escolha do usuário | Duas estratégias sobre o mesmo transcript |
| Persistência inicial | NDJSON append-only atrás de `TranscriptStore` | O transcript é um log; banco só se justifica quando houver consulta real |
| App Sandbox | Desligado | Obrigatório para dar spawn no `claude` do usuário |

### 3.1 Consequência de distribuição

Com o App Sandbox desligado, a distribuição é Developer ID + notarização.
A Mac App Store está fora. Isso é inescapável: um app sandboxed não consegue
executar binários fora do próprio bundle nem acessar `~/.claude`.

## 4. Arquitetura

### 4.1 Abstração de harness

```swift
protocol Harness {
    static var id: HarnessID { get }                        // .claudeCode, .codex, .opencode
    func discover() async throws -> HarnessInstallation     // binário, versão, saúde
    func capabilities(for: HarnessInstallation) -> HarnessCapabilities
    func start(_ spec: SessionSpec) async throws -> any HarnessSession
}

protocol HarnessSession {
    var events: AsyncStream<SessionEvent> { get }           // já normalizado
    func send(_ turn: UserTurn) async throws
    func resolve(_ request: PermissionRequest.ID, _ d: PermissionDecision) async throws
    func interrupt() async throws
    func stop() async
}
```

Tipos de apoio:

```swift
struct SessionSpec {
    let sessionID: UUID              // gerado por nós, vira --session-id
    let workingDirectory: URL
    var model: String?
    var permissionMode: PermissionMode
    var resuming: UUID?              // harnessSessionID de um segmento anterior
    var additionalDirectories: [URL]
}

struct UserTurn { var text: String; var attachments: [Attachment] }

enum PermissionDecision {
    case allow(updatedInput: JSONValue?)
    case deny(reason: String)
}
```

`HarnessCapabilities` declara o que cada harness suporta: trocar modelo em
sessão, alterar modo de permissão a quente, retomar sessão, fork. A UI lê as
capabilities e oculta o que não é suportado, em vez de oferecer ações que
falham. É o que impede a abstração de virar ficção.

#### Vocabulário canônico de ferramentas

Harnesses nomeiam ferramentas de forma diferente (`Edit` no Claude Code, outro
nome no Codex). O replay depende de significado equivalente entre eles.

Solução: um vocabulário canônico pequeno — `read`, `write`, `edit`, `execute`,
`search`, `fetch` — mais um envelope `raw` com o payload original preservado
na íntegra. O canônico serve ao handoff e à UI; o `raw` garante que nada é
perdido e permite round-trip fiel dentro do harness de origem.

### 4.2 Modelo de domínio

**Uma sessão do DevSpace não é uma sessão do harness.** Se o usuário troca de
Claude para Codex e continua, a conversa é um objeto nosso, durável, e cada
harness hospeda apenas um trecho dela.

```swift
struct Session {              // o que o usuário chama de "a conversa"
    let id: UUID
    var title: String
    var workingDirectory: URL
    var segments: [Segment]   // ordenados
}

struct Segment {              // um trecho contínuo dentro de um harness
    let id: UUID
    let harness: HarnessID
    let harnessSessionID: UUID     // o --session-id que nós geramos
    var model: String
    var entries: [TranscriptEntry]
    var usage: UsageTotals         // tokens e custo deste trecho
    var seededBy: Handoff?         // .briefing(texto) | .replay(até a entrada N)
}
```

O handoff é uma operação natural do modelo: fecha o segmento atual, abre o
próximo com outro harness, semeado por briefing ou replay. O transcript da
sessão é a concatenação dos segmentos, e a proveniência fica registrada.

Rastreio de custo sai de graça: tokens acabam por provedor, `usage` é por
segmento e agregado por sessão.

#### Entradas do transcript

Semânticas, não visuais. Cada uma com id estável, timestamp e envelope `raw`:

`userMessage`, `assistantText`, `assistantThinking`, `toolCall`, `toolResult`,
`permissionRequest`, `permissionDecision`, `systemNotice`, `turnResult`.

Requisito duro: o transcript é um **registro semântico fiel**, não um log de
exibição. O replay depende de ele ser completo.

### 4.3 Persistência

```swift
protocol TranscriptStore {
    func append(_ entry: TranscriptEntry, to: Segment.ID) async throws
    func load(_ session: Session.ID) async throws -> Session
    func list() async throws -> [SessionSummary]
}
```

Primeira implementação: um diretório por sessão, um NDJSON por segmento, mais
um `session.json` com metadados. Zero dependências, legível com `cat` quando
algo der errado, e natural para um log append-only.

**Gatilho para revisitar:** quando listar sessões ficar perceptivelmente lento,
ou quando houver busca por conteúdo. Aí o SQLite entra, com base em padrões de
consulta reais em vez de especulação. O `TranscriptStore` é a costura que torna
essa troca invisível para as camadas acima.

Não usamos SwiftData: o núcleo é um pacote headless testável sem UI, e
SwiftData é desconfortável fora do mundo SwiftUI/main-actor.

### 4.4 Adaptador Claude Code

#### Descoberta do binário

Dois problemas reais, ambos verificados:

1. `/opt/homebrew/bin/claude` é symlink para um caminho versionado
   (`/opt/homebrew/Caskroom/claude-code/2.1.236/claude`). Resolver e guardar o
   caminho final quebra no próximo `brew upgrade`. Guardamos o caminho lógico.
2. Um app macOS aberto pelo Finder **não herda o `PATH` do shell**. `claude`
   não existe do ponto de vista do app.

Solução: resolver via shell de login (`$SHELL -l -c 'command -v claude'`) na
inicialização, com fallback para locais conhecidos, e revalidar quando um
spawn falhar.

#### Invocação

```
claude -p \
  --output-format stream-json \
  --input-format stream-json \
  --include-partial-messages \
  --verbose \
  --session-id <uuid> \
  [--resume <uuid>] \
  [--model <model>] \
  [--permission-mode <mode>]
```

Com `cwd` no diretório de trabalho da sessão. O `--session-id` permite que o
DevSpace **gere** a identidade da sessão em vez de descobri-la depois.

#### Camadas

| Camada | Responsabilidade |
|---|---|
| `ProcessTransport` | `Process` + pipes; enquadra NDJSON (buffer de linha parcial, teto de 8 MiB por linha); drena stderr continuamente |
| `ControlProtocol` | Demultiplexa stdout: mensagens de conversa vs. requests de controle; tabela de pendentes por id; responde em stdin |
| `ClaudeEventMapper` | JSON bruto → modelo normalizado; vocabulário canônico + envelope `raw` |

**stderr precisa ser drenado sempre.** Um pipe de stderr cheio trava o processo
filho, e o sintoma é uma sessão que congela sem erro nenhum.

#### Eventos efêmeros vs. entradas duráveis

`--include-partial-messages` emite deltas de token. Se cada delta virasse uma
entrada, um turno viraria centenas de entradas no store.

São dois fluxos com tempos de vida diferentes:

- `SessionEvent` — efêmero, vai para a UI delta a delta.
- `TranscriptEntry` — durável, nasce consolidado quando o turno fecha.

O `Segment` guarda o segundo. O cockpit consome o primeiro.

## 5. Ciclo de vida e falhas

### 5.1 Sessão quente e fria

Em `stream-json` o processo fica vivo aceitando turnos até o stdin fechar. Com
muitas sessões abertas isso seriam muitos processos residentes.

Três estados:

| Estado | Significado |
|---|---|
| `idle` | Só existe no store, zero processo |
| `hot` | Processo vivo, aguardando turno |
| `working` | Turno em andamento |

`idle → hot` é `--resume`, barata e sem perda. Um reaper derruba para `idle`
toda sessão `hot` sem atividade por **5 minutos** (configurável). Sessões em
`working` nunca são derrubadas. O custo visível é um pequeno atraso no primeiro
turno após reativar.

### 5.2 Processos órfãos

Se o DevSpace morrer, processos `claude` sobrevivem consumindo recursos
invisivelmente. Duas defesas: matar o grupo de processos no encerramento
normal, e gravar pids ativos num arquivo de runtime para varrer órfãos no
próximo lançamento.

### 5.3 Taxonomia de erro

| Classe | Tratamento |
|---|---|
| `DiscoveryFailure` | Binário ausente ou versão incompatível; UI aciona instalação/atualização |
| `SpawnFailure` | Permissão, diretório inválido; acionável |
| `AuthFailure` | Usuário não autenticado no CLI; mensagem específica — é a causa mais provável de falha inicial |
| `SessionExit` | CLI terminou com código de erro |
| `ProtocolFailure` | Ver política abaixo |

### 5.4 Política de tolerância de protocolo

`ProtocolFailure` acontece quando o Claude Code atualiza e emite algo que o
mapper não conhece. **Este é o risco número um do projeto**, porque o protocolo
de controle não é contrato público.

**Tolerância por construção: um tipo de evento desconhecido nunca é erro.** Ele
é preservado no envelope `raw`, exibido como bloco cru na UI, registrado como
aviso, e a sessão continua. O mapper reconhece o que conhece e deixa o resto
passar intacto.

Isso transforma "o protocolo pode mudar" de risco existencial em incômodo
cosmético. Após um `brew upgrade`, na pior hipótese um tipo novo aparece feio
na tela até ser mapeado. Nada é perdido no store — o `raw` guardou tudo, e um
mapper corrigido consegue reinterpretar o histórico depois.

### 5.5 Interrupção

Vai pelo protocolo de controle. Sem resposta em **5 segundos**, `SIGTERM`;
sem saída em mais **3 segundos**, `SIGKILL`. O transcript registra que o turno foi interrompido — sem
isso, o replay reconstrói uma conversa que nunca aconteceu.

### 5.6 Permissão pendente no fechamento

Morre com o processo, registrada como `.expired`. Na retomada, o harness pede
de novo.

## 6. Estratégia de teste

O `harness-probe` grava sessões reais em NDJSON. Esses arquivos viram fixtures,
e a partir daí mapper, store e previews de UI rodam contra sessões de verdade
sem gastar token nem tocar na rede.

| Nível | Contra o quê | Custo |
|---|---|---|
| Mapper | Fixtures NDJSON | Rápido, determinístico |
| Transporte / protocolo | Binário falso que fala o protocolo | Testa enquadramento, stderr, morte de processo |
| Integração | `claude` real | Marcados, sob demanda; gastam tokens |

## 7. Estrutura do projeto

```
DevSpace/
├── Packages/HarnessKit/          # headless, zero dependências
│   ├── Sources/
│   │   ├── HarnessCore/          # protocolos, domínio, TranscriptStore
│   │   ├── ClaudeHarness/        # transporte, protocolo de controle, mapper
│   │   └── harness-probe/        # executável de diagnóstico
│   └── Tests/
└── DevSpace/                     # app SwiftUI, consome HarnessKit
```

## 8. Ordem de construção

Cada etapa entrega algo executável e verificável. As etapas 0 a 4 não têm UI,
por escolha deliberada: o risco do projeto está no protocolo, não na interface.

| # | Etapa | Entregável verificável |
|---|---|---|
| 0 | Esqueleto | Sandbox desligado, pacote criado e ligado ao app; compila, teste trivial passa |
| 1 | Descoberta | `harness-probe discover` imprime caminho e versão |
| 2 | Transporte + gravador | O JSON real do Claude Code sai no terminal; nasce o primeiro fixture |
| 3 | Protocolo de controle | `harness-probe` em modo `manual` pergunta "permitir Bash?" e a sessão obedece |
| 4 | Mapper + store | Sessão real gravada, recarregada do disco e reimpressa idêntica |
| 5 | Primeira janela | SwiftUI: lista de sessões, sessão aberta, streaming ao vivo, diálogo de permissão |

A etapa 2 é a que responde a única questão técnica genuinamente aberta deste
design (seção 11).

## 9. Fora de escopo da fundação

Handoff entre harnesses, adaptador do Codex, busca, UI de custo.

Todos já estão **acomodados** pelo modelo — `Segment`, `HarnessCapabilities` e
`TranscriptStore` existem exatamente para recebê-los — mas construí-los agora
seria projetar contra um segundo harness que ainda não temos na mão.

O adaptador do Codex é o que vai provar se a abstração da seção 4.1 é real, e
ele vem depois de a primeira estar de pé.

## 10. Riscos

| Risco | Severidade | Mitigação |
|---|---|---|
| Protocolo de controle muda entre versões do CLI | Alta | Tolerância por construção (5.4); `raw` preserva tudo; fixtures detectam regressão |
| `PATH` ausente em app lançado pelo Finder | Média | Resolução via shell de login (4.4) |
| Processos órfãos após crash | Média | Grupo de processos + varredura de pids (5.2) |
| Abstração de harness modelada só contra o Claude Code | Média | `capabilities` desde o dia 1; Codex como prova real logo após a fundação |
| Fidelidade do replay entre harnesses | Média | Transcript semântico + vocabulário canônico; briefing como alternativa sempre disponível |

## 11. Questões em aberto

**O formato exato das mensagens do protocolo de controle não foi verificado
empiricamente.** Foram confirmados: os flags, os modos de permissão e a
existência do protocolo. Não foi confirmado: o shape concreto de cada request
e response.

Isto não é uma lacuna do design — é o primeiro entregável dele. A etapa 2 liga
o transporte, grava o que sai e o mapper é desenhado contra dados reais. É a
razão de a construção começar pelo núcleo headless.

## 12. Ambiente verificado

Tudo abaixo foi confirmado na máquina de desenvolvimento em 2026-09-16:

- `claude` 2.1.236, em `/opt/homebrew/bin/claude` (symlink para caminho versionado do Homebrew Cask)
- Swift 6.4, Xcode 27.0, target `arm64-apple-macosx26.0`
- Modos de permissão: `acceptEdits`, `auto`, `bypassPermissions`, `manual`, `dontAsk`, `plan`
- Flags disponíveis: `--session-id`, `--include-partial-messages`, `--input-format`, `--output-format`, `--resume`, `--fork-session`, `--add-dir`, `--model`, `--permission-mode`, `--allowed-tools`, `--disallowed-tools`
- Autenticação no Keychain, não em arquivo — nunca a tocamos; o processo `claude` resolve sozinho
- `~/.claude/projects/*/*.jsonl` contém tipos internos (`atis-latch`, `ai-title`, `file-history-snapshot`, `last-prompt`) — formato privado e instável, **não** deve ser lido
