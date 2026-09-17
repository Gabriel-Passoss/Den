# Protocolo do Claude Code — o que foi observado no fio

**Data:** 2026-09-17 · **CLI:** claude 2.1.236 · **Modo:** `-p` com `--output-format stream-json --input-format stream-json --include-partial-messages --verbose`

Este documento registra o que a Etapa 2 descobriu empiricamente. Ele responde
parte da questão em aberto da spec §11 e, mais importante, delimita o que
**continua** sem resposta indo para o próximo plano.

Fonte: os três fixtures em `Packages/HarnessKit/Tests/ClaudeHarnessTests/Fixtures/`
(356 linhas). A procedência de cada um está no README ao lado deles.

## Respondido: o formato de entrada

A hipótese do plano estava correta e foi aceita sem alteração na primeira
tentativa:

```json
{"type":"user","message":{"role":"user","content":"<texto>"}}
```

Uma linha por turno, NDJSON, escrita no stdin.

## Respondido: os tipos de mensagem de saída

Contagem sobre os três fixtures:

| type | n |
|---|---|
| `stream_event` | 298 |
| `system` | 30 |
| `assistant` | 15 |
| `user` | 7 |
| `rate_limit_event` | 3 |
| `result` | 3 |

Subtipos de `system`: `init` 3, `thinking_tokens` 11, `status` 10, `permission_denied` 6.

Cada arquivo começa com exatamente um `system/init` e termina com exatamente
um `result` (`is_error: false`, `terminal_reason: "completed"`).

## Achado que confirma a spec §4.4: entrega dupla do texto do assistente

O texto do assistente chega **duas vezes** — incrementalmente via
`stream_event` e depois completo via uma linha `assistant`.

Isso valida empiricamente a distinção que a spec §4.4 propõe entre
`SessionEvent` (efêmero, para a UI, delta a delta) e `TranscriptEntry`
(durável, para o store, consolidado no fim do turno). **O mapper precisa
escolher a fonte por destino.** Consumir as duas para o mesmo destino duplica
cada turno no transcript.

## EM ABERTO: o protocolo de controle nunca apareceu

**Os três fixtures contêm zero linhas de `control_request` ou
`control_response`.** Verificado por varredura.

Em modo headless, o CLI resolveu tudo sozinho:

- Leituras via Bash (`ls`) executaram **sem nenhum portão de permissão**, mesmo
  com `--permission-mode manual` passado explicitamente.
- Redirecionamento de saída do shell foi bloqueado como **categoria de
  sandbox** — não como decisão de permissão. A mensagem cita o caminho de
  destino *dentro* do diretório permitido e manda usar a ferramenta Write.
  Chega como `system/permission_denied` mais um `tool_result` sintético de erro.
- `system/init` reporta `permissionMode: "default"` mesmo tendo recebido
  `--permission-mode manual`.

**Consequência para o próximo plano:** a spec §11 continua sem resposta quanto
ao shape concreto de cada request e response de controle. A hipótese de
trabalho — não verificada — é que o `canUseTool` do SDK dependa de um handshake
`initialize` do protocolo de controle no qual o cliente anuncia que sabe
responder, e que o nosso probe nunca envia. **Não tratar como fato.** O
primeiro entregável do plano do protocolo de controle deve ser confirmar ou
refutar isso, do mesmo jeito que a Etapa 2 confirmou o formato de entrada.

Não desenhe em cima da suposição de que uma sessão vai travar esperando
aprovação: sob as condições testadas, nenhuma travou.

## Verificação do protocolo de controle (2026-09-17)

A hipótese acima foi testada. **Refutada na forma simples.**

### Estabelecido empiricamente

O canal de controle **está vivo** em modo headless `stream-json`. Um
`control_request` de `initialize` escrito no stdin recebe resposta:

```jsonc
// enviado
{"type":"control_request","request_id":"init-1","request":{"subtype":"initialize"}}
// recebido
{"type":"control_response","response":{"subtype":"success","request_id":"init-1",
  "response":{"commands":[...]}}}
```

Mas **enviar `initialize` não habilita o roteamento de `can_use_tool`.** Duas
sessões idênticas, uma com handshake e outra sem, terminaram ambas em
`system/permission_denied` sem nenhum `control_request` vindo do CLI.

### Estabelecido por análise do binário

O CLI 2.1.236 tem a instalação completa do lado servidor:

- `sendRequest({subtype:"can_use_tool", tool_name, display_name, input, permission_suggestions})`
- tabela de pendentes, detecção de descasamento de nome, `control_cancel_request`
- subtipos presentes: `initialize`, `can_use_tool`, `interrupt`,
  `set_permission_mode`, `set_model`, `hook_callback`, `mcp_message`

O request de `initialize` aceita `hooks`, `sdkMcpServers` e
`webSearchIsolationExemptMcpServers` — **não há campo declarando suporte a
permissões**.

A negação é governada por `toolPermissionContext.shouldAvoidPermissionPrompts`,
ligado por uma camada de permissão `avoid_prompts`. E a escolha do avaliador é
`canUseTool: contexto.canUseTool ?? hasPermissionsToUseTool` — ou seja, o
callback do cliente é uma **opção** do contexto, com a lógica embutida como
padrão.

### Confundidor que limita a conclusão

As duas sessões rodaram sob as configurações da máquina de teste, que têm
`permissions.defaultMode: "auto"`, e o `--permission-mode manual` passado na
linha de comando **não surtiu efeito** — o `system/init` reportou
`permissionMode: "default"` nas duas. Hooks do usuário também rodaram dentro
da sessão.

Portanto: **não está demonstrado que o modo `manual` não pergunta.** Está
demonstrado que `initialize` sozinho não é o interruptor.

### RESPONDIDO: a chave é uma flag oculta

O SDK oficial resolveu a questão. Quando um callback `can_use_tool` é
configurado, o SDK **não negocia nada pelo protocolo** — ele acrescenta uma
flag na linha de comando:

```
--permission-prompt-tool stdio
```

O valor literal `stdio` faz o CLI rotear os pedidos de permissão pelo protocolo
de controle em vez de resolvê-los sozinho.

Confirmado em duas fontes independentes:

1. O SDK Python documenta que `_configure_can_use_tool` devolve uma cópia das
   opções com `permission_prompt_tool_name="stdio"`.
2. O binário 2.1.236 instalado contém o código correspondente:
   `if(canUseTool){ if(permissionPromptToolName) throw Error("canUseTool
   callback cannot be used with permissionPromptToolName..."); push("--permission-prompt-tool","stdio") }`

**A flag não aparece em `claude --help`.** É por isso que a Etapa 2 não a
encontrou: procuramos na ajuda, e ela não está lá.

O `initialize` continua sendo necessário por outras razões (hooks, servidores
MCP do SDK), mas **não** é o que habilita permissões.

### CONFIRMADO na prática (2026-09-17)

Uma sessão com `--permission-prompt-tool stdio` produziu o pedido, e a resposta
do cliente foi honrada — `prova.txt` foi criado. Gravado em
`Packages/HarnessKit/Tests/ClaudeHarnessTests/Fixtures/permission-request.ndjson`.

O que o CLI envia:

```json
{"type":"control_request",
 "request_id":"a7c8532d-65be-4a74-8a3f-bd2f485e9a61",
 "request":{"subtype":"can_use_tool",
   "tool_name":"Write",
   "display_name":"Write",
   "input":{"file_path":"/private/tmp/probe-scratch/prova.txt","content":"ok"},
   "description":"prova.txt",
   "permission_suggestions":[{"type":"setMode","mode":"acceptEdits","destination":"session"}],
   "tool_use_id":"toolu_01MnTatUeYfz3cMti4VXq4z8"}}
```

O que o cliente responde para permitir:

```json
{"type":"control_response",
 "response":{"subtype":"success","request_id":"<mesmo id>",
   "response":{"behavior":"allow","updatedInput":{...}}}}
```

Note o `permission_suggestions`: o CLI já sugere a regra que o usuário
provavelmente quer ("aceitar edições nesta sessão"). Isso é material direto de
UI — é o botão "permitir sempre nesta sessão" pronto, vindo do próprio harness
em vez de inventado por nós.

### Ressalva que ainda vale

O SDK documenta que o callback só é invocado quando as regras de permissão do
CLI avaliam para **"ask"**. Não é chamado para ferramentas já liberadas por
`allowed_tools`, por `permission_mode` (`acceptEdits`/`bypassPermissions`), por
regras em `permissions.allow`, nem depois de um hook `PreToolUse` responder
allow.

Isso explica o confundidor das rodadas de teste: sob `defaultMode: "auto"` das
configurações da máquina, muitas chamadas nunca chegam a "ask".

### Contrato do protocolo de controle, agora conhecido

Do SDK oficial, sem custo. Envelope:

```jsonc
{"type":"control_request","request_id":"<id>","request":{"subtype":"...", ...}}
{"type":"control_response","response":{"subtype":"success","request_id":"<id>","response":{...}}}
{"type":"control_response","response":{"subtype":"error","request_id":"<id>","error":"..."}}
```

Subtipos que o cliente envia: `initialize` (`hooks`, `agents`, `skills`,
`systemPromptSnapshot`, `excludeDynamicSections`, `forwardSubagentText`),
`interrupt`, `set_permission_mode` (`mode`), `hook_callback`
(`callback_id`, `input`, `tool_use_id`), `mcp_message`, `rewind_files`,
`mcp_reconnect`, `mcp_toggle`, `stop_task`.

Subtipo que o CLI envia ao cliente: **`can_use_tool`**, com `tool_name`,
`input`, `tool_use_id`, e opcionalmente `permission_suggestions`,
`blocked_path`, `decision_reason`, `title`, `display_name`, `description`,
`agent_id`.

Nota: o SDK também injeta `CLAUDE_CODE_ENTRYPOINT` no ambiente do subprocesso
(`sdk-py` no caso do Python). Vale replicar com um valor próprio do DevSpace.

### Achado lateral com valor imediato

O CLI aceita **`--max-budget-usd <amount>`**, um teto de gasto por sessão que
só funciona com `--print`. O DevSpace deveria passá-lo por padrão: é a
proteção mais direta contra uma sessão descontrolada, e teria evitado os dois
incidentes de custo desta implementação.

## Nota operacional

O transporte nunca inspeciona conteúdo — ele entrega linhas de `Data` cruas,
sem parse, sem schema, sem validação. Um tipo de evento desconhecido é
fisicamente incapaz de falhar nessa camada, que é exatamente o substrato que a
política de tolerância da spec §5.4 exige.

A única chave de desligamento dependente de conteúdo é o teto de 8 MiB por
linha, e atingi-lo é **terminal**. Um CLI que emita uma linha gigante — uma
imagem em base64 num resultado de ferramenta, por exemplo — mataria a sessão em
vez de degradar. Vale reconsiderar quando o mapper existir.
