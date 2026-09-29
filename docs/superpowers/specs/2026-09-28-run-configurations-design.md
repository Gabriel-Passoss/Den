# Configurações de execução — rodar projetos sem sair do DevSpace

**Data:** 2026-09-28
**Status:** Entrega 1 construída; entregas 2 e 3 pendentes
**Referência de produto:** *Run Configurations* do IntelliJ

## 1. Contexto e objetivo

Hoje, para subir a API ou o front de um projeto enquanto conversa com o agente,
é preciso abrir um terminal por fora do app, lembrar o comando, a pasta e as
variáveis de ambiente. O objetivo é que o DevSpace guarde **como cada projeto
roda** e deixe o usuário subir, parar e acompanhar os processos por dentro,
com o log ao lado da conversa.

**Critério de sucesso:** abrir o DevSpace, clicar ▶ numa configuração e ver o
log colorido chegando no painel lateral; clicar ■ e o processo (com todos os
filhos) morrer, sem porta presa.

### 1.1 Decisões do usuário

| Tema | Decisão |
|---|---|
| O que é "projeto" | A **pasta de trabalho**. Conversas na pasta ou em subpastas veem as mesmas configs. Guardadas no app, fora do repositório. |
| Convivência com o painel de Alterações | **Um de cada vez**: dois botões na toolbar trocam o conteúdo do mesmo espaço lateral. |
| Log | **Só leitura, com cores ANSI**. Sem stdin, sem terminal completo. |
| Extras na primeira versão | **Detecção de scripts**, **configs compostas** e **uma instância só**. |
| Escopo do painel | **Só o projeto atual.** |
| Integração com o chat | **Ainda não.** Copiar e colar resolve por enquanto. |
| Camada de execução | **Abordagem A**: pseudo-terminal próprio com grupo de processos. |

### 1.2 Por que a execução não reaproveita o `ProcessTransport`

O `ProcessTransport` do HarnessKit usa `Process` com pipes e, ao terminar, mata
só o filho direto. Para um harness isso basta. Para um `npm run dev`, que cria
`npm → node → vite/esbuild`, matar o `npm` deixa o `node` órfão segurando a
porta. Além disso, sem um terminal do outro lado, muitas ferramentas desligam
as cores e passam a acumular a saída em buffer. Por isso a execução tem um
mecanismo próprio (§4.2).

## 2. Modelo de dados

```swift
struct RunConfiguration: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var kind: Kind

    enum Kind: Codable, Equatable {
        case command(CommandSpec)
        case compound([UUID])
    }
}

struct CommandSpec: Codable, Equatable {
    var command: String
    var workingDirectory: String
    var environment: [EnvVar]
}

struct EnvVar: Codable, Equatable, Identifiable {
    let id: UUID
    var key: String
    var value: String
}
```

- `command` é uma linha na sintaxe do shell do usuário (`$SHELL`), a mesma que
  ele digitaria no terminal.
- `workingDirectory` é relativo à raiz do projeto; `""` é a própria raiz. Se
  começar com `/`, é absoluto.
- `environment` é uma lista ordenada, para a tabela da UI manter a ordem que o
  usuário digitou.

### 2.1 Regras

- **Nome** obrigatório e único dentro do projeto (comparação sem diferenciar
  maiúsculas).
- **Comando** obrigatório em configs de comando.
- **Compostas** só referenciam configs `.command` do mesmo projeto. Composta
  dentro de composta não existe, o que elimina ciclos sem validação.
- Remover uma config tira o id dela de todas as compostas do projeto.
- Uma composta sem filhas fica com ▶ desabilitado.
- **Uma instância só** é o comportamento fixo, não uma opção: ▶ numa config
  que já está rodando reinicia (para, espera sair, sobe de novo).

### 2.2 Persistência

Arquivo JSON em `~/Library/Application Support/DevSpace/run-configurations.json`:

```json
{ "version": 1, "projects": { "/Users/x/www/api": [ { "id": "…", "name": "API", "kind": … } ] } }
```

- `RunConfigurationStore` recebe a URL do arquivo por injeção; os testes usam
  uma pasta temporária.
- Gravação atômica (`Data.write(to:options: .atomic)`).
- Arquivo ausente vale como vazio. Arquivo ilegível é renomeado para
  `run-configurations.corrupt-<timestamp>.json` e o app segue com vazio, com
  um `print` do motivo, no padrão das sessões ilegíveis do `WorkspaceModel`.
- Projetos cuja pasta sumiu continuam no arquivo; limpeza não entra nesta versão.

### 2.3 Descoberta do projeto de uma conversa

`RunProjectLocator`, função pura, a partir da `workingDirectory` da conversa:

1. o ancestral mais próximo, incluindo a própria pasta, que já tem configs
   salvas;
2. senão, a raiz do repositório git (subida procurando `.git`);
3. senão, a própria pasta da conversa.

A subida procurando `.git` hoje está embutida em
`GitChangesModel.discoverRepoRoots`. Ela é extraída para uma função
reutilizável (`GitRepository.toplevel(containing:)`), usada pelos dois.

### 2.4 Detecção de scripts

`RunScriptDetector` examina a raiz do projeto e as subpastas de primeiro nível
(monorepos com `apps/web`), ignorando as mesmas pastas que o
`GitChangesModel` já pula (`node_modules`, `.build`, `dist`…). Cada detector é
uma função pequena que devolve `[RunSuggestion]`:

| Arquivo | Sugestão |
|---|---|
| `package.json` | um `<gerenciador> run <script>` por entrada em `scripts`. Gerenciador pelo lockfile na mesma pasta: `pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, `bun.lockb`/`bun.lock` → bun, senão npm. |
| `Makefile` | `make <alvo>` para cada alvo declarado no início da linha (`nome:`), exceto `.PHONY`, alvos com `%`, alvos que começam com `.` e atribuições (`:=`, `::=`). |
| `compose.yaml`, `compose.yml`, `docker-compose.yml`, `docker-compose.yaml` | `docker compose up`. |

- O nome sugerido é o do script (`dev`). Em subpasta, leva a pasta como prefixo
  (`web: dev`) e a `workingDirectory` aponta para ela.
- Sugestões nunca são salvas sozinhas. Uma sugestão cujo par
  (comando, pasta) já existe como config não aparece.

## 3. Arquitetura

Feature nova em `DevSpace/Run/`, no mesmo formato de `DevSpace/Git/`:

```
DevSpace/Run/
  Models/     RunConfiguration, LogBuffer, RunSuggestion
  Services/   RunConfigurationStore, RunProjectLocator, RunScriptDetector,
              ShellEnvironment, PTYProcess, ANSIParser
  Views/      RunPanel, LogView, RunConfigurationsWindow, CommandForm,
              CompoundForm, EnvironmentTable
  RunConfigurationsModel.swift
  RunManager.swift
  RunInstance.swift
DevSpace/App/
  RunCommands.swift   (menu Executar)
  AppDelegate.swift   (encerramento dos processos ao sair)
```

| Unidade | Responsabilidade | Depende de |
|---|---|---|
| `RunConfigurationsModel` | `@Observable`. Configs por projeto, CRUD, regras da §2.1, grava pelo store. | `RunConfigurationStore` |
| `RunManager` | `@Observable`. Uma `RunInstance` por config, a regra de uma instância só, compostas, `stopAll()`. | `ProcessLaunching`, `ShellEnvironment` |
| `RunInstance` | `@Observable`. Uma execução: estado, início, `LogBuffer`. | handle de processo |
| `PTYProcess` | Pseudo-terminal, `posix_spawn`, leitura, saída, parada por grupo. | Darwin |
| `ShellEnvironment` | Ambiente completo do shell do usuário, resolvido uma vez. | executor injetável com timeout |
| `ANSIParser` | Bytes → linhas estilizadas, com estado entre pedaços. | nada |
| `LogBuffer` | Linhas com limite e mudanças incrementais para a view. | nada |

`RunConfigurationsModel` e `RunManager` vivem no nível do `DevSpaceApp` (e não
do `ContentView`), porque a janela de configuração e todas as janelas
principais precisam enxergar o mesmo estado. Chegam às views por
`.environment`. Trocar de conversa não afeta nenhum processo.

O `RunManager` não conhece o `PTYProcess` diretamente: recebe um
`ProcessLaunching` por injeção, como o `WorkspaceModel` recebe o
`HarnessRegistry`, para os testes usarem um lançador falso.

## 4. Execução

### 4.1 Ambiente do shell

Apps abertos pelo Finder não herdam o `.zshrc`, então `nvm`, `pyenv` e parte
do Homebrew ficam fora do PATH. O `ShellEnvironment` roda uma vez por
execução do app, no primeiro ▶:

```
$SHELL -l -i -c 'env -0'
```

com timeout de 5s. O shell vem de `getpwuid(getuid()).pw_shell`, não da
variável `SHELL`. A saída separada por `\0` vira o dicionário base.

O `SystemCommandRunner` do HarnessKit não serve aqui: ele não tem timeout nem
como matar o filho, e um `.zshrc` que pergunta algo ("atualizar o
oh-my-zsh? [Y/n]") travaria para sempre. O `ShellEnvironment` recebe por
injeção um executor próprio, que mata o shell ao estourar o prazo; os testes
passam um executor falso.

- Se falhar ou estourar o tempo, usa o ambiente do app acrescido de
  `/opt/homebrew/bin` e `/usr/local/bin` no PATH, e a primeira linha do log de
  cada execução avisa: "Não consegui carregar o ambiente do seu shell; usando
  o PATH padrão".

Ambiente final de um processo, do mais fraco para o mais forte:
ambiente do shell → `TERM=xterm-256color`, `COLORTERM=truecolor` → `LANG`
padrão → variáveis da config.

O `LANG` padrão existe porque o launchd não define locale e o shell do usuário
costuma não definir (quem define é o Terminal ou o iTerm). Sem ele, Ruby, `ls`
e `git` rodariam no locale C e tratariam acento como ASCII. Só entra quando
nem `LANG`, nem `LC_ALL`, nem `LC_CTYPE` vieram do shell, e vale
`<idioma do sistema>.UTF-8` se esse locale existir em `/usr/share/locale`,
senão `en_US.UTF-8`.

### 4.2 `PTYProcess`

1. `openpty` com janela fixa de 160×50 (redimensionamento dinâmico fica fora).
2. `posix_spawn` de `$SHELL -c "<comando>"` na pasta resolvida, com
   `POSIX_SPAWN_SETSID` (sessão e grupo novos, pgid = pid) e `file_actions`
   ligando o lado escravo a stdout e stderr e, no stdin, a ponta de leitura de
   um pipe que o DevSpace mantém aberto e nunca escreve: não é terminal (um
   prompt falha rápido em vez de travar) e nunca chega ao fim (ferramentas como
   `esbuild --watch`, que encerram quando o stdin fecha, continuam rodando). Com
   `POSIX_SPAWN_CLOEXEC_DEFAULT`, o filho não herda nenhum outro descritor.
3. O pai fecha o lado escravo e lê o mestre numa fila de fundo
   (`DispatchSourceRead`). No macOS, o fim da leitura chega como `EIO`, não
   como 0; os dois valem como fim.
4. A saída do processo é detectada por `DispatchSource.makeProcessSource(.exit)`
   seguido de `waitpid`, que dá o código de saída (ou o sinal que o matou).

**Parar:** `kill(-pgid, SIGTERM)`, até 5s de espera, `kill(-pgid, SIGKILL)`. A
espera é pelo **grupo inteiro**, não só pelo processo principal: a parada só
termina quando `kill(-pgid, 0)` falha com `ESRCH`. Um neto lento (o JVM do
Quarkus rodando os ganchos de encerramento) ainda segura a porta depois que o
shell morre, e o ↻ não pode subir o processo novo antes disso. Enquanto isso a
linha fica em "Parando…"; um ↻ ou um fechamento do app no meio de uma parada
espera por ela.

### 4.3 Estados

```
starting → running(pid) ─→ exited(status)
    │            └→ stopping → stopped
    ├──────────────────────→ stopped    (■ antes do spawn)
    └──────────────────────→ failed(message)
```

- `failed` é para quando o spawn nem acontece: pasta inexistente, shell
  inválido. A mensagem vai para o log.
- `stopped` é a parada pedida pelo usuário (■, ↻ ou saída do app) e mostra
  "Parado", em cinza, qualquer que seja o status com que o processo morreu.
- `exited` carrega o status (`ProcessExit.code(Int32)` ou `.signal(Int32)`)
  de um processo que terminou sozinho: código 0 mostra "Encerrado", em cinza;
  código diferente de 0 mostra "Saiu com código N" e sinal mostra "Encerrado
  pelo sinal N", os dois em vermelho.
- Comando inexistente não é `failed`: o shell imprime o erro e sai com 127,
  que aparece como qualquer outra saída.
- O log de uma instância encerrada fica visível até o próximo ▶ ou até
  "Limpar". Logs não sobrevivem ao fechamento do app.

### 4.4 `ANSIParser` e `LogBuffer`

O parser recebe `Data` em pedaços arbitrários e guarda estado entre eles:

- UTF-8 multibyte cortado na borda do pedaço fica pendente até o próximo;
- sequência de escape cortada idem;
- **SGR** (`ESC[…m`) muda o estilo corrente: reset, negrito, esmaecido,
  itálico, sublinhado, 16 cores + claras, 256 cores e truecolor, frente e
  fundo;
- `\n` fecha a linha; `\r` volta ao início da linha corrente, e o texto
  seguinte a sobrescreve (barras de progresso não viram mil linhas);
  `ESC[2K`/`ESC[K` limpam a linha corrente;
- qualquer outro CSI (movimento de cursor, limpar tela), OSC (títulos,
  hiperlinks) e caracteres de controle restantes são descartados.

**Destaque por nível** (`LogHighlighter`, aplicado pelo `LogRenderer` ao
desenhar, sem tocar no buffer, na cópia nem na busca): linhas de erro
(`ERROR`, `FATAL`, `FAIL`, `ERR!`, `npm error`, `TypeError`/`IOException`,
`Error:`, `error:`/`error[`, `error TS…`, `panic:`, `Traceback`) em vermelho;
aviso (`WARN`, `WARNING`, `warning`, `warn`, `…Warning`) em amarelo;
`DEBUG`/`TRACE` esmaecidas; em `INFO` só a palavra esmaece. Vale o nível mais
grave da linha, e só os trechos que a ferramenta mandou sem cor são pintados.

O `LogBuffer` guarda até 20.000 linhas e descarta as mais antigas. Ele expõe
as mudanças como uma lista de operações, para a view aplicar sem redesenhar:
`append([Line])`, `replaceLast(Line)`, `dropFirst(Int)`, `clear`. As mudanças
são entregues ao main actor em lotes de ~60ms, como o streaming do chat.

### 4.5 Encerramento do app

Um `AppDelegate` (via `@NSApplicationDelegateAdaptor`) responde
`applicationShouldTerminate` com `.terminateLater` quando há processos vivos,
chama `RunManager.stopAll()` (SIGTERM em todos os grupos, até 2s, depois
SIGKILL) e então responde ao sistema.

### 4.6 Processos nunca sobrevivem ao DevSpace

Cada comando sobe por um wrapper em `/bin/sh` (`PTYProcess.guardScript`): ele
deixa em segundo plano, no mesmo grupo, um guardião que lê o pipe do stdin — cuja
ponta de escrita só o DevSpace segura — e então faz `exec` do shell do usuário
com o comando, mantendo pid e grupo. Quando o pipe fecha, o guardião manda
`SIGTERM` ao grupo e, 3s depois, `SIGKILL`. O pipe fecha em dois casos:

- o DevSpace morre de qualquer jeito (crash, Forçar Encerrar, `kill`, Stop do
  Xcode) — o kernel fecha os descritores dele;
- o shell do comando termina — o DevSpace fecha o pipe ao registrar a saída,
  então filhos deixados em segundo plano (`server &`) também caem.

O guardião só passa a ignorar `SIGTERM` depois de o pipe fechar, para garantir o
`SIGKILL` final quando o DevSpace morreu. Num ■ normal ele morre junto com o
resto do grupo e não atrasa a espera da parada.

Verificado em 2026-09-28: o caminho sem guardião não servia, porque o macOS não
torna o pseudo-terminal o terminal controlador do filho (exigiria
`ioctl(TIOCSCTTY)` no filho, que o `posix_spawn` não permite) e fechar o mestre
não entrega `SIGHUP`.

Continua fora do alcance: processos que saem do grupo por conta própria
(`docker compose up -d`, daemons), como aconteceria num terminal.

## 5. Interface

Todos os textos visíveis em português, com a primeira palavra maiúscula.

### 5.1 Toolbar e painel lateral

- O `@AppStorage("DevSpace.gitInspector")` booleano vira
  `@AppStorage("DevSpace.inspector")` com um enum `InspectorPane`
  (`changes`, `run`; vazio = fechado). Migração: `true` no valor antigo vira
  `changes`.
- Botão **Alterações** (⌥⌘0) já existente e botão novo **Execução** (⌥⌘9,
  símbolo `play.rectangle`). Clicar no do painel aberto fecha; clicar no outro
  troca o conteúdo do mesmo `.inspector`.
- O botão Execução mostra um ponto verde quando há algo rodando no projeto da
  conversa aberta.
- Largura do painel de Execução: mín. 320, ideal 560, máx. 784.

### 5.2 Painel de Execução

```
┌ Execução · api                    [⚙] [x] ┐
│ ● API          Rodando · 12min    [↻] [■] │
│ ● Web          Saiu com código 1      [▶] │
│ ◇ Full stack   2 de 3 rodando     [▶] [■] │
├───────────────────────────────────────────┤
│ API                  [Copiar] [Limpar] [↓]│
│ VITE v5.2  ready in 312 ms                │
│ ➜  Local:   http://localhost:5173/        │
└───────────────────────────────────────────┘
```

- **Cabeçalho:** "Execução · <nome da raiz>", caminho completo no `.help`;
  ⚙ abre a janela de configuração do projeto.
- **Lista:** configs do projeto atual, na ordem salva. Ponto verde rodando,
  amarelo iniciando ou parando, vermelho quando saiu sozinho com erro (§4.3),
  cinza parado ou nunca rodou. Botões: ▶ quando parado; ↻ e ■ quando rodando.
- **Compostas:** ícone próprio e resumo "N de M rodando". ▶ inicia todas as
  filhas (reiniciando as que já rodam); ■ para as que estão rodando.
- **Seleção:** clicar numa config de comando mostra o log dela embaixo. Ao
  dar ▶, a config passa a ser a selecionada. Clicar numa composta mostra a
  lista das filhas com o estado de cada uma, clicáveis para ver o log.
- **Log:** `LogView`, um `NSTextView` embrulhado em `NSViewRepresentable`, só
  leitura, selecionável, fonte monoespaçada de 11pt. Aplica as operações do
  `LogBuffer` direto no `NSTextStorage`. ⌘F abre a barra de busca nativa
  (`usesFindBar`). Rolagem automática enquanto o usuário está no fim; pausa ao
  subir; o botão ↓ volta ao fim e religa. "Copiar" copia o log inteiro em
  texto puro; "Limpar" esvazia o buffer.
- **Vazio:** "Nenhuma configuração neste projeto" e o botão "Configurar…".
  Se o detector achou algo, acrescenta "Encontrei N scripts" com o arquivo de
  origem.

Um SwiftUI `LazyVStack` não é usado no log porque 20.000 linhas coloridas
chegando ao vivo travariam a lista; o TextKit lida com isso nativamente.

### 5.3 Janela "Configurações de execução"

`WindowGroup(id: "run-configurations", for: String.self)`, com o caminho da
raiz do projeto como valor: abrir de novo para o mesmo projeto traz a janela
existente para frente. Título: "Configurações de execução · <nome da raiz>".

```
┌ Configurações de execução · api ─────────────────────┐
│ [+▾] [−] [⧉]    │ Nome       [API                  ] │
│ API             │ Comando    [npm run dev          ] │
│ Web             │ Pasta      [apps/api          ][…] │
│ Full stack      │ Variáveis  ┌ Chave ─┬ Valor ─┐    │
│ ── Sugestões ── │            │ PORT   │ 3000   │    │
│ + npm: build    │            └────────┴────────┘    │
│ + make: test    │                          [+] [−]  │
└──────────────────────────────────────────────────────┘
```

- **Barra da lista:** + com menu (Comando, Composta); − remove (se a config
  estiver rodando, para antes); ⧉ duplica com o nome "<nome> (cópia)".
- **Formulário de comando:** Nome, Comando (campo de várias linhas), Pasta
  (`RunFolderPicker`: lista das pastas do projeto com busca, "Raiz do projeto"
  sempre no topo, ◆ e o arquivo marcador nas pastas que parecem projeto —
  `package.json`, `Makefile`, `Cargo.toml`, `Package.swift`, `go.mod`,
  `pyproject.toml`, `Gemfile`, `compose.yaml`, `docker-compose.yml`; até 4
  níveis e 2.000 pastas, pulando ocultas e as pesadas de `ProjectScan`; uma
  pasta salva que não está na lista aparece no topo, com "Não existe" se
  sumiu), Variáveis (tabela editável de chave e valor). Já está no formulário
  da entrega 1.
- **Formulário de composta:** Nome e uma lista de checkboxes com as configs de
  comando do projeto.
- **Salvamento automático**, no estilo do macOS, sem OK/Aplicar. Mudanças
  valem no próximo ▶. Nome vazio ou repetido fica marcado no campo e não é
  gravado até ser corrigido. Pasta inexistente gera aviso no campo, sem
  bloquear.
- **Sugestões:** seção abaixo das configs; um clique cria a config e a
  seleciona.

### 5.4 Menu Executar

`RunCommands`, um `CommandMenu("Executar")` que lê o projeto da conversa em
foco por `focusedSceneValue`, no padrão do `HarnessCommands`:

- um item por config do projeto ("Executar API"; "Reiniciar API" quando já
  roda);
- "Parar tudo" (para as instâncias do projeto);
- "Mostrar painel de execução" (⌥⌘9);
- "Editar configurações…".

Sem conversa aberta, os itens ficam desabilitados.

## 6. Testes

**Unitários puros:**
- `ANSIParser`: cada tipo de SGR, reset, UTF-8 e escape cortados entre
  pedaços, `\r` sobrescrevendo, `ESC[2K`, descarte de CSI/OSC.
- `LogBuffer`: limite de linhas com `dropFirst`, `replaceLast` após `\r`,
  `clear`.
- `RunScriptDetector`: pastas temporárias com cada tipo de arquivo, escolha do
  gerenciador pelo lockfile, prefixo em subpasta, pastas ignoradas.
- `RunProjectLocator`: as três regras e a precedência entre elas.
- `RunConfigurationStore`: ida e volta, arquivo ausente, arquivo corrompido.
- `RunConfigurationsModel`: nome único, remoção limpando compostas, filtro de
  sugestões já existentes.
- `ShellEnvironment`: parsing de `env -0` com um executor falso;
  fallback em erro e em timeout.

**Integração com processos reais** (`/bin/sh`, comandos curtos, sem
asserções de relógio apertadas):
- a saída chega pelo pseudo-terminal e `test -t 1` confirma terminal;
- o código de saída e a morte por sinal são repassados;
- ■ mata um neto (`sh -c 'sleep 60 & echo $!; wait'` e depois `kill(pid, 0)`
  falha);
- um processo com `trap '' TERM` escala para `SIGKILL`.

**`RunManager` com `ProcessLaunching` falso:** reinício pela regra de uma
instância só, composta iniciando e parando filhas, `stopAll`.

**UI:** se a infraestrutura de XCUITest (`DevSpaceUITests`,
`LaunchEnvironment.swift`) estiver disponível no branch, cobre abrir o painel,
criar uma config e ver a primeira linha do log. Senão, a verificação é rodando
o app.

## 7. Ordem de entrega

Cada entrega termina com algo que o usuário usa de ponta a ponta.

1. **Rodar e ver o log.** `ShellEnvironment`, `PTYProcess`, `ANSIParser`,
   `LogBuffer`, `RunConfigurationStore`, `RunProjectLocator`,
   `RunConfigurationsModel` (só configs de comando), `RunManager`, o painel com
   a lista e o log, o botão da toolbar com o enum `InspectorPane`, o
   encerramento ao sair, e um formulário mínimo "Nova configuração" (nome,
   comando, pasta) num sheet dentro do próprio painel.
2. **Janela de configuração.** A janela completa, variáveis de ambiente,
   duplicar, remover, o menu Executar. O sheet da entrega 1 é trocado pela
   janela.
3. **Detecção e compostas.** `RunScriptDetector`, sugestões na janela e no
   estado vazio do painel, configs compostas no modelo, no painel e no menu.

## 8. Fora de escopo

- Entrada no processo (stdin), terminal completo, TUIs.
- Integração com o chat (enviar log, @menção de processo).
- "Antes de rodar" (tarefas que precedem outra).
- Várias instâncias da mesma config.
- Painel com processos de outros projetos.
- Configs versionadas no repositório (`.devspace/run.json`).
- Redimensionar o pseudo-terminal conforme a largura do painel.
- Guardar logs entre execuções do app.
- Limpar processos órfãos depois de um crash (a menos que o `SIGHUP` da §4.6
  resolva de graça).
- Detectores além dos três da §2.4.
