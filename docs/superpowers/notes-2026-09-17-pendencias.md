# Pendências conhecidas ao fim da Etapa 3

Registradas aqui porque os workspaces de plano são apagados e o git é o que
sobra. Nenhuma bloqueia o merge; todas foram julgadas em review e deliberadamente
adiadas, com o raciocínio.

## Da camada de protocolo

**`responseData` vaza `EncodingError`.** O `respond` chama
`try decision.responseData(requestID:)` fora do `do/catch`, então um erro de
codificação escapa por uma API documentada como lançando `ChannelError`.
Alcance estreito: o encoder do `JSONValue` só lança em `.double(.nan/.infinity)`,
que não chega pelo fio (não é JSON válido) — só um consumidor montando
`updatedInput` à mão o produz. **A correção honesta é um caso próprio de
`ChannelError`**, não dobrar em `.channelClosed`, que seria a mesma desonestia
um nível acima. Fazer junto com o trabalho de `.expired` da §5.6, que o conjunto
de pendentes agora viabiliza.

**`control_cancel_request` não é classificado.** A análise do binário mostra que
o CLI o possui. Hoje cai em `.conversation`, então um id de permissão cancelado
permanece em `outstandingPermissions` e o `respond` ainda escreveria resposta
para ele. Não é regressão — antes o `respond` aceitava qualquer coisa — mas o
conjunto novo torna isso endereçável pela primeira vez.

**`record` nunca captura quadro de controle.** Ele não passa
`--permission-prompt-tool stdio`, de propósito: com a flag, toda gravação
congelaria no primeiro pedido de permissão. A consequência é que fixtures
gravados por ele são estruturalmente cegos ao protocolo de controle — o mesmo
ponto cego que fez a Etapa 2 não achar a flag. Se um plano futuro quiser tráfego
de controle gravado, o `record` precisa de um respondedor ou de um parâmetro no
`make`.

**A ligação `main.swift` → `ClaudeLaunch.make` não tem teste automatizado.** Um
alvo executável com `main.swift` não pode ser importado por alvo de teste. O
argv é testado na origem; o uso dele não.

## Da concorrência

**Escrita bloqueante é sistêmica.** O `writeSync` faz `write(2)` bloqueante
segurando o mutex. Seguindo cada chamador: `send`/`respond` travam o ator do
`ControlChannel` (e com ele o `stop()`); `writeTurn` trava o ator do
`ProcessTransport` (e com ele o `terminate()`). Contra a §5.5: um harness que
pare de drenar o stdin faz o `send(.interrupt)` bloquear, o prazo nunca disparar
— o job de timeout está no ator travado — e a escalada para SIGTERM ficar
inalcançável. **A garantia da §5.5 é inatingível exatamente no estado para o
qual a §5.5 existe.**

Na escala: cada escrita bloqueada estaciona uma thread do pool cooperativo. Com
N sessões travadas acima do número de núcleos, o pool esgota e todo trabalho
assíncrono de fundo do DevSpace para.

A correção real é `O_NONBLOCK` mais fila de escrita. É trabalho de porte e
pertence à Etapa 5 — mas o tamanho da conta deve estar escrito enquanto o
raciocínio está fresco.

**O `refuse` é a primeira escrita bloqueante automática no caminho de leitura.**
Roda dentro do pump segurando o ator. Um harness que emita um `control_request`
irreconhecível e então pare de drenar o próprio stdin travaria o canal. É a
mesma classe acima, documentada no ponto de chamada; a alternativa rejeitada
(despachar num `Task`) trocaria um risco raro por um comum.

## Menores, com o gatilho que os torna relevantes

- `.object` do `JSONValue` usa `Dictionary`: ordem de chaves não sobrevive ao
  round-trip. Morde quando envelopes `raw` forem comparados byte a byte contra
  fixtures — provável teste de regressão do mapper da Etapa 4.
- O teto de 8 MiB por linha é **terminal**. Uma CLI futura que emita uma linha
  gigante (uma imagem em base64 num resultado de ferramenta) mataria a sessão em
  vez de degradar. O `FramingError.lineTooLong` carrega só o limite: nem prefixo
  da linha ofensora, nem contagem de bytes. É o único incidente que não dá para
  diagnosticar pelo erro.
- Três asserções de relógio (`< 1s`) nos testes de terminate e de neto. Têm 10x
  de folga sobre o mecanismo, mas contrariam a restrição global do plano e são
  as primeiras a falhar numa máquina de CI carregada.
- O `refusalMessage` é `internal`, então um consumidor fora do módulo não
  consegue comparar contra ele.

# Pendências conhecidas ao fim da Etapa 4a (transcript durável)

Mesmo critério: nenhuma bloqueia o merge, todas foram julgadas no review final
do transcript durável e deliberadamente adiadas, com o raciocínio.

## O buraco de tolerância que sobrou

**Payloads de discriminadores CONHECIDOS não são tolerantes.** O endurecimento
da Etapa 4a chegou até a camada do DISCRIMINADOR — `TranscriptEntry.Kind` e
`Handoff` degradam um nome de caso desconhecido para `.unrecognized` — e parou
ali. O INTERIOR de um caso conhecido continua sendo `Codable` sintetizado sobre
tipos fechados.

O contraexemplo não é hipotético: a spec §5.6 já AGENDA um
`PermissionDecision.expired`. No dia em que ele existir, uma versão futura
grava `{"permissionDecision":{"_1":{"expired":{...}},"requestID":"r1"}}`, o
leitor de hoje reconhece `permissionDecision` perfeitamente bem, entra no
decode sintetizado de `PermissionDecision`, e estoura — descartando a entrada
INTEIRA, `raw` e tudo. Medido no review: 3 linhas escritas, 2 lidas.

O comentário em `FileTranscriptStore.entries(of:in:)` que descreve o que chega
ali como "JSON genuinamente quebrado" está um nível raso demais por causa
disso, e o comentário foi corrigido para dizê-lo. A correção de verdade é dar
aos enums fechados aninhados (`PermissionDecision` primeiro) o mesmo caso de
fuga que `Kind` e `Handoff` têm — é mudança de porte e pertence ao plano do
mapper, junto com o trabalho de `.expired` da §5.6 que já está nesta lista pelo
lado do protocolo.

## Do modelo

- **Permissão expirada e interrupção não têm representação de primeira classe**
  (§5.5, §5.6). Pertencem ao plano de orquestração.
- **`Segment.usage` é estado derivável que o store nunca deriva.** Nada diz qual
  das duas fontes manda — o campo gravado no `session.json` ou a soma dos
  `turnResult` do NDJSON. Enquanto ninguém as compara, elas não discordam; o
  primeiro relatório de custo as compara.
- **`harnessSessionID: UUID` assume que todo harness aceita identidade gerada
  pelo chamador.** A spec §4.2 escreve `UUID` literalmente, então o código é
  fiel — mas é o vazamento de forma a vigiar quando o segundo adaptador chegar.

## Do store

- **`list()` engole a falha de ler a RAIZ.** O `try?` sobre
  `contentsOfDirectory(at: root,…)` devolve `SessionListing()` — a mesma
  resposta que uma raiz vazia. Para a raiz AUSENTE isso é deliberado e está
  pinado por `listOnAnEmptyOrMissingRootIsEmptyNotAnError`: no primeiro uso do
  app o diretório ainda não existe, e "nenhuma sessão" é a resposta certa. O
  que não se distingue dela é permissão negada ou disco ilegível — aí "nenhuma
  sessão" é mentira, e é a mesma forma de perda silenciosa que o
  `SessionListing.unreadable` acabou de consertar um nível ABAIXO, por sessão.
  Some-se que `list()` é declarado `throws` e hoje não lança de lugar nenhum.
  O conserto é distinguir `ENOENT` do resto: ausente devolve vazio, o resto
  sobe. Achado do re-review da onda de correção, fora do escopo do que ele
  media; barato de fazer no primeiro plano que tocar o store.

## Menores da Etapa 4a que sobreviveram às correções

Registrados aqui porque o workspace do plano que os guardava é descartável.

- **`Handoff.replay(throughEntry:)` não valida que a entrada existe.** Nada
  impede um replay apontando para um `UUID` que não está em segmento nenhum da
  sessão. Vira relevante no plano de handoff — é a feature de trocar de harness
  mantendo a sessão, e um ponteiro de corte inválido só apareceria na hora de
  montar o prompt de retomada.
- **`Session.segments` documenta ordem cronológica sem impor.** O tipo aceita
  qualquer ordem; `allEntries` concatena na ordem do array. Quem montar a
  retomada depende disso estar certo.
- **O formato de data é decidido pelo store, não pelos tipos.** `.iso8601` está
  fixado pelos testes do `FileTranscriptStore`; nada em `TranscriptEntry` ou
  `Session` guia outro codificador. Um segundo escritor (export, IPC) escolheria
  sozinho.
- **O default de `Segment.seededBy` não é exercitado por teste direto** — os
  helpers sempre o passam explicitamente. Mutá-lo passa despercebido; mutar a
  atribuição é pego. Lacuna no código de teste do plano, não no de produção.
- **A janela de corrida da guarda de newline não tem teste.** Combinar processo
  morto no meio de uma escrita com um segundo escritor simultâneo é o único
  cenário vivo; o pior resultado é uma linha em branco que o filtro já descarta.
  Reconhecida e benigna, não coberta.

## Teste instável observado

- `respondFailsWithChannelClosedWhenTheWriteHitsADeadPipe` falhou **uma vez em
  ~10 execuções da suíte inteira**, e **zero em 20 execuções isoladas**. Nada da
  Etapa 4a é alcançável a partir dele (`ControlChannel` não toca nenhum tipo
  deste plano). É sensível a carga, o que o põe na mesma família da pendência
  "escrita bloqueante é sistêmica" registrada acima: o erro esperado depende de
  o `write(2)` no pipe morto de fato retornar `EPIPE` dentro da janela do teste.

# Pendências conhecidas ao fim da Etapa 4b (mapeador de eventos)

Mesmo critério: nenhuma bloqueia o merge, julgada na Task 6 e deliberadamente
adiada, com o raciocínio.

## Do store

**`FileTranscriptStore` trunca a fração de segundo do carimbo.** Descoberto ao
escrever a Task 6, no teste que leva o corpus de `permission-denied.ndjson`
inteiro até o disco e de volta: o encoder usa `.iso8601`, que não escreve
milissegundos, enquanto as linhas `assistant` e `user` do protocolo trazem
carimbos com fração de segundo ("…:59.447Z"). Um carimbo que vai ao disco
volta truncado no segundo. Não afeta a ordem do transcript — que é a ordem de
append no NDJSON, não a do carimbo — nem nenhum teste existente (o teste da
Task 6, `theMappedTranscriptSurvivesTheStore`, compara carimbos com tolerância
de 1s em vez de igualdade, exatamente por essa razão), mas é perda de
fidelidade contra a §4.2. Mudar a estratégia de codificação de data é mudança
de formato de arquivo e pertence a um plano próprio que toque o store.

# Pendências conhecidas ao fim da Etapa 4b — revisão final de branch

Mesmo critério: nenhuma bloqueia o merge. Estas cinco vieram da revisão final
de todo o branch `feat/claude-event-mapper` (253 testes verdes, build limpo),
julgadas junto com a onda de correção que endereçou o bug real da revisão (a
tabela de verbos faltando `Glob`/`Grep`) e deliberadamente adiadas com o
raciocínio abaixo.

## A costura de permissão

**A costura entre `ControlChannel` e `ClaudeEventMapper.entry(for:raw:)` não
tem chamador que consiga ser fiel.** `ControlChannel.consume` (em
`ControlChannel.swift`) classifica o quadro, tem o `Data` cru na mão, e o
descarta ao devolver `.permissionRequest(request)`; `PermissionRequest`
(`HarnessCore/Permission.swift`) não tem campo `raw` para carregá-lo adiante.
Consequência medida hoje: um pedido de permissão não é registrado em
DOBRO — o mapeador devolve `.empty` para quadros de controle, então há
exatamente um dono — mas é DESCARTADO por inteiro. Rodar `permission-request.ndjson`
pela linha através de `ClaudeEventMapper.map(line:)` dá 6 entradas, e nenhuma
delas é `.permissionRequest` ou `.permissionDecision` — as duas linhas de
controle (`control_response` do `init` e o `control_request` do `can_use_tool`)
caem no `case "control_request", "control_response": return .empty`. E
`noFixtureLineDegrades` passa mesmo assim, porque descartar não é degradar —
o teste só vigia `.unrecognized`, não ausência. Direção do conserto: carregar
`raw: JSONValue` em `ChannelOutput.permissionRequest` ou no próprio
`PermissionRequest`, para que um chamador real (que ainda não existe — é o
mesmo buraco que o comentário de `ClaudeEventMapper+Permission.swift` agora
documenta explicitamente) tenha o que passar.

## O fluxo efêmero não sabe nomear uma chamada de ferramenta em streaming

`content_block_start` é descartado em `ephemeral(_:)` (cai no `default` que
comenta "moldura do stream"), e é o ÚNICO quadro que carrega o nome da
ferramenta durante o streaming — o nome só chega quando a linha `assistant`
pousa como `.toolCall`, já consolidada. Medido em `permission-denied.ndjson`:
63 quadros `input_json_delta` sem nome de ferramenta para mostrar enquanto o
JSON do input é montado pedaço a pedaço. Junto disso, uma assimetria: existe
`SessionEvent.turnStarted` (de `message_start`) mas não existe contraparte de
fim de turno — quem consome só `events` sabe que um turno começou e nunca que
ele terminou (isso só aparece em `entries`, na linha `assistant` consolidada
ou no `.turnResult`). Direção do conserto: um caso novo de `SessionEvent` que
carregue o índice do bloco, o tipo do bloco e o nome da ferramenta — sem
quebrar o "sem estado" do mapeador, porque tudo isso é derivável da própria
linha `content_block_start` em mãos. Deliberadamente diferido: a forma certa
desse caso deveria ser puxada pelo cockpit que vai consumi-lo, que ainda não
existe; inventá-la agora arrisca errar o formato e reescrever goldens medidos
para um comportamento que ninguém lê ainda.

## `system/init` inventa string vazia onde deveria admitir que não sabe

Em `system(_:)`, `case "init"`: `line["model"]?.stringValue ?? ""` e
`line["session_id"]?.stringValue ?? ""` — um `system/init` sem `model` (ou sem
`session_id`) emite `.sessionInitialized(model: "", harnessSessionID: "")` em
vez de degradar. O modelo é a proveniência do segmento inteiro da sessão; um
modelo vazio é uma mentira silenciosa onde `.unrecognized` seria honesto e
visível. Diferido porque o que a camada de sessão DEVE fazer diante de um
`init` sem modelo — recusar o segmento? aceitar com um rótulo "desconhecido"? —
é decisão dela, não do mapeador.

## Uma forma plausível de `user` que o corpus não exercita

Uma linha `user` cujo `content` é um array de blocos `text` (em vez do array
de `tool_result` que o corpus sempre traz, ou da string que só nós escrevemos)
cai em `userBlock(_:at:)`, falha a guarda de `tool_result` e degrada para
`claude:content/text` em vez de virar `.userMessage`. Nenhuma das quatro
fixtures grava essa forma — o CLI observado nunca ecoou um turno de usuário em
blocos —, mas é uma forma plausível para o turno inicial ecoado de uma sessão
retomada (`--resume`), que este corpus não cobre. Registrado como nota, não
como defeito: não há fixture para confirmar a forma real do campo nesse caso.

## `timestamp(of:)` pode estar cego a um formato de carimbo que o corpus não usa

`timestamp(of:)` (`ClaudeEventMapper.swift`) tenta
`Date.ISO8601FormatStyle(includingFractionalSeconds: true)` e depois
`Date.ISO8601FormatStyle()` — ambos exigem o sufixo `Z`. As linhas do corpus
sempre usam `Z` ("…:59.447Z"), nunca um offset explícito tipo `+00:00`. Se o
CLI algum dia emitir um carimbo em forma de offset, ele cairia
silenciosamente no relógio injetado em vez de falhar de forma visível —
exatamente o comportamento que a spec §5.4 pede para JSON malformado, mas
aplicado aqui a um formato de data que pode ser perfeitamente válido e só não
reconhecido. Não verificado contra o protocolo real: registrado como pergunta
em aberto, não como defeito confirmado.

## Observado ao rodar o cockpit numa máquina real (2026-09-17)

### Os `system` de hook não estão no corpus, e são a maioria na vida real

Primeira execução do cockpit contra o `claude` do usuário: o transcript abriu
com **nove** entradas `.unrecognized` antes da conversa começar — eventos de
hook (`subtype=hook_started`, `subtype=hook_response`, com `hook_event`,
`hook_id`, `hook_name` e a saída do hook).

Nenhuma fixture tem um único hook, porque `harness-probe record` grava com
`--setting-sources ""`. É a MESMA classe de erro que a revisão final pegou na
tabela de verbos canônicos: o corpus não é o protocolo, é uma configuração —
e uma configuração deliberadamente mais pobre que a de qualquer máquina de
trabalho.

O que NÃO foi feito, de propósito: acrescentar `hook_started`/`hook_response`
à lista de subtipos efêmeros do mapeador. Seria adivinhar forma de fio não
medida, exatamente o defeito que a revisão apontou em D5. O que foi feito: a
UI recolhe corridas consecutivas de `.unrecognized` num bloco fechado — o
conteúdo continua lá (spec §5.4) e para de afogar a conversa.

Para decidir de verdade é preciso medir. E há uma distinção provável dentro do
par: `hook_started` não carrega semântica nenhuma (é "começou"), mas
`hook_response` carrega o `additionalContext` que o hook INJETA na conversa —
isto é, texto que o modelo de fato viu. Descartá-lo tornaria o transcript
infiel à §4.2, e é o tipo de coisa que só se descobre lendo a linha. Uma
regravação de fixture com hooks ligados resolveria os dois de uma vez.

### Bloco de raciocínio sem texto

Um `assistantThinking` chegou com corpo vazio (só a assinatura criptográfica),
e a UI desenhava o rótulo "RACIOCÍNIO" com nada embaixo. Corrigido na
apresentação — `append` descarta texto vazio. Não foi mexido no mapeador: uma
entrada de raciocínio vazia é fiel ao que veio no fio, e o `raw` guarda a
assinatura.
