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

## Nota operacional

O transporte nunca inspeciona conteúdo — ele entrega linhas de `Data` cruas,
sem parse, sem schema, sem validação. Um tipo de evento desconhecido é
fisicamente incapaz de falhar nessa camada, que é exatamente o substrato que a
política de tolerância da spec §5.4 exige.

A única chave de desligamento dependente de conteúdo é o teto de 8 MiB por
linha, e atingi-lo é **terminal**. Um CLI que emita uma linha gigante — uma
imagem em base64 num resultado de ferramenta, por exemplo — mataria a sessão em
vez de degradar. Vale reconsiderar quando o mapper existir.
