# Fixtures NDJSON — procedência

Transcritos reais de sessões do Claude Code, gravados pelo `harness-probe` em
2026-09-16. São os bytes contra os quais o mapper de eventos vai ser escrito, e
nenhum deles é sintético.

## Como cada um foi produzido

Todos com o mesmo comando, variando só `--prompt` e `--out`, sempre a partir de
`Packages/HarnessKit`:

```sh
.build/debug/harness-probe record \
  --prompt "<o prompt da tabela abaixo>" \
  --cwd /tmp/probe-scratch \
  --out <arquivo>.ndjson
```

| Arquivo | Linhas | Prompt |
|---|---|---|
| `hello.ndjson` | 12 | `Diga apenas OK e nada mais.` |
| `tool-use.ndjson` | 55 | `Liste os arquivos do diretório atual usando o bash.` |
| `permission-denied.ndjson` | 289 | `Crie um arquivo chamado novo.txt com o conteúdo 'oi' usando o bash.` |

`/tmp/probe-scratch` era um diretório descartável com dois `.txt` e uma subpasta
— nunca este repositório. Ele aparece nos fixtures como `/private/tmp/probe-scratch`,
que é o caminho resolvido pelo macOS.

O `harness-probe` monta a invocação real; ela não está nos fixtures, então fica
registrada aqui:

```
claude -p --output-format stream-json --input-format stream-json \
  --include-partial-messages --verbose --session-id <uuid> \
  --safe-mode --permission-mode manual
```

## O que saber antes de escrever um teste contra estes bytes

- **Versão do CLI: `claude` 2.1.236.** É o que está em
  `system/init.claude_code_version` nos três arquivos. O protocolo não é
  contrato público (spec §5.4) — uma versão diferente pode emitir campos
  diferentes.

- **`/Users/probeuser` é uma redação, não um caminho real.** O nome de usuário
  do operador aparecia em caminhos absolutos de plugin e na saída de `ls -la`
  dentro de um `tool_result`; foi substituído por `probeuser` com um `sed`
  depois da gravação. Nenhum outro campo foi editado, e as 356 linhas seguem
  sendo JSON válido. Não tente resolver esse caminho — ele não existe em
  máquina nenhuma.

- **`permissionMode` vem como `"default"` no `system/init`, mesmo tendo sido
  passado `--permission-mode manual`.** Verificado nos três arquivos. Ou o
  campo reporta outra coisa que não o modo efetivo, ou o CLI não propaga a flag
  para o `init`. Não assuma que este campo espelha o que foi pedido.

- **`plugins`, `skills` e `slash_commands` variam por máquina.** Aqui: 11
  plugins (com caminhos absolutos), 15 skills, 47 slash commands — o inventário
  instalado do operador. `--safe-mode` impede que hooks e plugins **executem**,
  mas não remove esse inventário do `system/init`. Um teste que compare esses
  campos falha na máquina de qualquer outra pessoa.

- **`messaging_socket_path`** (`/tmp/cc-socks/<pid>.sock`) é efêmero e já não
  existe.

- Os dados de custo (`total_cost_usd`, `modelUsage`) foram mantidos.

## Regravar

Custa dinheiro real e alguns minutos. Por isso o `harness-probe record` recusa
sobrescrever um `--out` que já existe: para regravar, apague o arquivo
explicitamente primeiro. Não existe `--force`.
