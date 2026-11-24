# FakeCLI

Os testes de ponta a ponta do Den não falam com o Claude Code nem com o
`opencode` de verdade: eles falam com o `Scripts/fake-cli/fake-cli`, um
script de shell que finge ser um harness CLI. Assim o transporte, o canal de
controle e o mapeador de eventos reais rodam inteiros, sem rede e sem conta
para pagar. `DenTestSupport/FakeCLI.swift` é a fachada que um teste usa para
roteirizar esse script.

Este documento descreve o contrato entre os dois, que é um protocolo de
arquivos — não dá para ler na assinatura dos métodos.

## Passos: gatilho e resposta

Um teste roteiriza o CLI em *passos*. Cada passo tem um gatilho e uma
resposta:

```swift
try cli.on(FakeCLI.userTurn, reply: RecordedSession.claude("hello"))
```

O CLI lê a entrada linha por linha. Quando uma linha **contém** o gatilho do
passo atual, ele imprime a resposta daquele passo e avança o contador. Os
passos são consumidos em ordem: o passo 2 só é considerado depois que o 1
disparou.

Duas coisas acontecem sem passo nenhum:

- `__ID__` em qualquer linha da resposta é substituído pelo id da última
  requisição JSON-RPC que o app mandou. É assim que uma resposta casa com a
  pergunta sem o teste adivinhar o id.
- Requisições de controle do Claude (interromper, trocar o modo de permissão)
  são respondidas com sucesso automaticamente.

Para simular uma queda em vez de uma resposta, o passo carrega um status de
saída e uma mensagem em stderr — de fora, é indistinguível de um crash:

```swift
try cli.on(FakeCLI.userTurn, exit: 1, stderr: "Error: invalid API key")
```

## Gatilhos prontos

Os gatilhos são trechos de JSON, porque é o que aparece na linha que o app
escreve. Os prontos cobrem os dois protocolos:

| Gatilho | Protocolo | Casa com |
|---|---|---|
| `FakeCLI.userTurn` | Claude stream-json | um turno do usuário na stdin |
| `FakeCLI.permissionAnswer` | Claude stream-json | a resposta do app a um pedido de permissão |
| `FakeCLI.request(_ method:)` | ACP | uma requisição JSON-RPC do app, pelo método |
| `FakeCLI.answer` | ACP | a resposta do app a uma requisição que o CLI mandou |

## Os dois construtores

Qual usar depende de quem precisa ler os arquivos:

- **`init()`** — para os testes unitários, que o app hospeda no mesmo
  processo. O app lê os arquivos do fake direto do disco, e `directory` e
  `state` são a mesma pasta em `/tmp`.
- **`init(appRoot:harness:)`** — para os testes de UI, que lançam o app como
  outro processo. O runner é sandboxed: o app não consegue executar nem ler o
  que o runner escreve. Então os passos viajam no `launchEnvironment` (um
  dicionário de arquivo → conteúdo em base64, na chave
  `FAKE_CLI_SCENARIO_<HARNESS>`) e o CLI guarda o estado dele sob o `root` que
  o teste passou.

É por isso que `directory` e `state` são separados: `directory` é onde o teste
escreve os passos, `state` é onde o CLI em execução guarda o contador e o que
ele viu.

## O que o teste lê de volta

- `received` — toda linha que o app escreveu na stdin do CLI. As barras
  escapadas do JSON são desfeitas, para um método aparecer como
  `session/prompt` e não `session\/prompt`. As consultas de uso de contexto
  são filtradas, porque chegam de forma assíncrona e tornariam a lista
  instável.
- `launches` — uma entrada por execução do CLI, com o diretório de trabalho e
  os argumentos. É o que prende a linha de comando que o app monta.

E dois atalhos para respostas que não passam pelo protocolo de passos:
`answerTitles(with:)` responde às execuções `-p` de uma tacada, que é como os
títulos de sessão são gerados, e `answerSuggestions(with:)` responde às
sugestões de resposta.

## Sessões gravadas

`RecordedSession` lê as sessões que o HarnessKit gravou dos CLIs reais, que
ficam nas fixtures de teste do pacote. Repetir essas gravações é o que prende
o app ao que os CLIs realmente emitem, em vez do que a gente imagina que eles
emitem — e é por isso que as fixtures são byte a byte e o
`.pre-commit-config.yaml` as exclui dos hooks de formatação.
