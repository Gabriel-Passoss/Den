# Testes

Três alvos: `DenTests` (unidade e ponta a ponta do app), `DenUITests` (XCUITest,
que roda do Xcode e não no CI — ver `docs/quality.md`) e os testes do pacote em
`Packages/HarnessKit/Tests`. `DenTestSupport` guarda o que os dois primeiros
compartilham, com destaque para o `FakeCLI` (ver `docs/fake-cli.md`).

Este documento descreve a infraestrutura compartilhada: o que cada helper
garante e a razão de ser de escolhas que parecem arbitrárias no código.

## Suites de defaults vêm de um pool

`ScratchDefaults` entrega uma suite de `UserDefaults` por teste. O detalhe que
explica o desenho: **toda suite deixa um plist em `~/Library/Preferences`**. O
`cfprefsd` escreve esse arquivo de forma preguiçosa, depois que o teste já
limpou a suite, então apagar as chaves não apaga o arquivo.

Se cada teste inventasse um nome novo, uma rodada completa deixaria centenas de
plists para trás. Por isso os nomes vêm de um **pool fixo**: uma suite liberada
é esvaziada e entregue ao próximo teste. Uma rodada deixa um arquivo por teste
que correu *ao mesmo tempo*, e a rodada seguinte reaproveita os mesmos
arquivos.

Os nomes do pool mudam por checkout, para duas worktrees rodando testes ao
mesmo tempo não esvaziarem a suite uma da outra.

## Esperar é parte da asserção, não cortesia

`withLiveChat` monta um `ChatModel` cujo registry só tem fakes. O stream de
updates é consumido por uma task destacada, então uma asserção sobre eventos
tem que **esperar** o consumo — ler logo depois de emitir testa o nada.

Quando a paciência acaba, o helper falha. Isso é deliberado: um `settle` que
desistisse em silêncio deixaria o teste verde provando nada, e passaria a ser
uma asserção decorativa. O mesmo vale para `refresh(_:until:)`.

A paciência dos testes de ponta a ponta (`processPatience`, 10 segundos) é
generosa de propósito, porque processos de verdade sobem ali; ela só estoura
quando algo está realmente errado.

## Ponta a ponta usa tudo de verdade, menos o CLI

`withEndToEnd` roda contra os harnesses, o transporte e o armazenamento de
transcript reais, com cada CLI apontado para um `FakeCLI`. Nada alcança um CLI
de verdade nem as sessões do próprio usuário.

Dois pontos do helper:

- `newChat(on:)` abre a conversa pelo mesmo caminho do botão "Nova conversa" e
  espera o CLI subir antes de devolver. Matar o processo antes disso perderia o
  registro do lançamento, que é justamente o que vários testes conferem.
- `relaunched()` abre um segundo workspace sobre o mesmo disco e as mesmas
  defaults — é o que o próximo lançamento do app veria. Todo workspace aberto
  fica registrado para ter o CLI parado no fim, mesmo se o teste lançar no meio.

`withWorkspace` segue a mesma ideia para o `WorkspaceModel`: suite e raiz
descartáveis, e o `seed` roda **antes** do model existir, para o teste poder
plantar chaves no formato antigo e exercitar a migração que acontece no `init`.

Os testes de git de ponta a ponta usam um repositório real dirigido pelo
`/usr/bin/git`, em vez de pastas `.git` falsas com porcelain de mentira. A
configuração do usuário não pode vazar para dentro deles: sem assinatura e sem
hooks.

## O log de um harness falso

O protocolo `Harness` exige um tipo `Sendable`, e os harnesses são structs. Para
o teste inspecionar o que o harness recebeu, `FakeHarness` carrega um
`HarnessLog`, que é uma classe — a referência compartilhada é o que permite o
teste ler o que a cópia do struct registrou.

## Testes de UI: o runner é sandboxed

`DenUITests` dirige o app de verdade pela árvore de acessibilidade. Cada teste
recebe a própria raiz de dados e os próprios CLIs falsos, então nenhuma sessão,
preferência ou CLI real é tocado.

O runner do XCUITest é sandboxed: ele lê de qualquer lugar mas escreve só
dentro do container dele, que o app não alcança. Por isso a raiz de dados
pertence ao app, debaixo de `/tmp`, e os passos dos CLIs falsos viajam no
`launchEnvironment` (ver `docs/fake-cli.md`).

Dois comportamentos do XCUITest que o código contorna, e que parecem bug se
você não souber:

- **Botões de um card respondem ao teste de hit como não clicáveis**, mesmo que
  um clique de verdade acerte. É por isso que existe o
  `clickThroughFailingHitTest`, que clica na coordenada central do elemento em
  vez de chamar `click()` direto.
- **A Touch Bar espelha os botões de um alerta.** Uma busca por
  `app.buttons["Apagar"]` acha dois elementos e fica ambígua, então a consulta
  tem que ser feita dentro do sheet (`app.sheets.buttons[...]`).

E uma nota de leitura de falha: o helper `require(_:in:)` anexa a árvore de
acessibilidade ao resultado quando um elemento não aparece. É o que se lê
quando uma query para de casar — normalmente porque um rótulo mudou.
