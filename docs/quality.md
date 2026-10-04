# Quality gates

Verificações automáticas em dois momentos. As que só olham o código rodam em
cada commit (via [pre-commit](https://pre-commit.com)) e de novo no CI; as que
precisam compilar ou executar os testes rodam só no CI, em todo pull request
(`.github/workflows/quality.yml` e `.github/workflows/tests.yml`), com as
mesmas versões das ferramentas.

## O que é verificado

| Gate | Ferramenta | Commit | CI |
|---|---|:-:|:-:|
| Formatação Swift (o estilo da casa, sem reescrever o que já é deliberado) | SwiftFormat 0.63.1 — `.swiftformat` | ✓ corrige sozinho | ✓ |
| Lint: falhas lógicas (`a == a`, force unwrap, `Task` que engole erro, observer descartado, `super` esquecido…), idiomas e limites de tamanho | SwiftLint 0.65.1 — `.swiftlint.yml` | ✓ | ✓ |
| Sem comentários novos em Swift; só diretivas de ferramenta passam | SwiftLint, regra `no_comments` | ✓ | ✓ |
| Fronteiras de módulo: HarnessKit sem framework de UI, harness concreto só em `Den/Harness`, `Den/Shared` sem `HarnessCore` | SwiftLint, regras customizadas em `.swiftlint.yml` | ✓ | ✓ |
| Código duplicado (clone novo de ≥ 50 tokens e ≥ 5 linhas) | jscpd 5.4.0 — `.jscpd.json` | ✓ | ✓ |
| Warnings do compilador viram erro (concorrência, deprecações, valores não usados, código inalcançável) | `swiftc` / `xcodebuild` — `Scripts/quality/build-strict` | | ✓ |
| Código não usado: declarações, parâmetros, imports, propriedades só atribuídas | Periphery 3.8.0 — `.periphery.yml` e `Packages/HarnessKit/.periphery.yml` | | ✓ |
| Piso de cobertura de linhas, por alvo do HarnessKit e para o app fora das pastas `Views` | `Scripts/quality/coverage` — `.coverage-floor.json` | | ✓ |
| Corridas de dados nos testes do pacote e do app | Thread Sanitizer — job `sanitizer` em `tests.yml` | | ✓ |
| Testes de mutação no HarnessKit, nas linhas que o PR alterou | `Scripts/quality/mutation` — `.mutation-baseline.json` | | ✓ só em PR |
| Segredos (chaves, tokens) | gitleaks 8.30.1 | ✓ no que está staged | ✓ no histórico inteiro |
| Mensagem de commit no formato Conventional Commits (`feat(app): …`) | conventional-pre-commit | ✓ | ✓ nos commits do PR |
| Scripts shell | shellcheck | ✓ | ✓ |
| Workflows do GitHub Actions (inclui shellcheck nos `run:`) | actionlint | ✓ | ✓ |
| Higiene: conflito de merge esquecido, nomes que colidem no APFS, arquivo grande, JSON/YAML/plist inválido, chave privada, espaço no fim da linha, LF | pre-commit-hooks | ✓ | ✓ |
| Testes dos próprios scripts de qualidade | `python3 -m unittest` — `Scripts/quality/tests` | ✓ se `Scripts/quality/` mudou | ✓ |

O build com warnings como erro e o Periphery precisam do Xcode e de um build
completo, por isso ficam só no CI (e no `Scripts/quality/check`, abaixo).

## Configurar a máquina

```sh
brew install pre-commit
pre-commit install --allow-missing-config   # hooks de pre-commit e de commit-msg
```

Os hooks ficam no `.git` principal, então valem para todas as worktrees do
repositório. Com `--allow-missing-config`, o hook passa direto numa branch que
ainda não tem o `.pre-commit-config.yaml`; sem a opção, o commit falharia ali.

Na primeira vez, `Scripts/quality/tool` baixa o SwiftLint (com o checksum
conferido) e compila o SwiftFormat a partir da tag fixada — leva um ou dois
minutos e fica guardado em `.build/quality-tools`. Se você já tiver a versão
exata no `PATH` (por exemplo via Homebrew), ela é usada direto.

O Xcode 16+ lê o `.editorconfig`, então o editor já indenta e termina linhas
do jeito que os hooks esperam.

## Onde o "porquê" fica

Código não leva comentário aqui (regra `no_comments`), então o que um
comentário carregaria e não cabe num nome fica em `docs/`:

- `docs/fake-cli.md` — o protocolo entre o `FakeCLI` e o script de shell que
  ele dirige: gatilhos, passos, `__ID__` e os dois construtores.
- `docs/harnesskit.md` — as decisões do pacote: por que nenhuma leitura
  bloqueia thread, por que o fim do stream carrega o motivo, e como um formato
  desconhecido sobrevive no transcript.
- `docs/testes.md` — a infraestrutura de teste: o pool de suites de defaults,
  por que esperar faz parte da asserção, e os comportamentos do XCUITest que os
  testes de UI contornam.

## No dia a dia

- **SwiftFormat mexeu no arquivo**: o commit para, o arquivo fica corrigido;
  confira com `git diff`, rode `git add` e commite de novo.
- **SwiftLint reclamou**: a mensagem diz a regra entre parênteses. Corrija; se
  for falso positivo de verdade, desligue só ali, com a diretiva e nada mais:
  `// swiftlint:disable:next force_unwrapping`.
- **Comentário recusado** (`no_comments`): o código não leva comentários; nome
  e estrutura carregam a intenção. Só diretivas de ferramenta passam
  (`swiftlint:`, `swiftformat:`, `periphery:`, `jscpd:` e o
  `swift-tools-version:` do manifesto do pacote), sem texto depois.
- **Import recusado** (`headless_harnesskit`,
  `concrete_harness_outside_registry`, `shared_knows_no_harness`): a
  dependência cruza uma fronteira de módulo. O HarnessKit não conhece UI, o
  app só fala com um harness concreto por `Den/Harness`, e `Den/Shared` não
  conhece harness nenhum.
- **jscpd achou um clone novo**: o relatório marca com `[NEW]` os dois trechos.
  Extraia o que é comum. Se a repetição for intencional, envolva o trecho com
  `// jscpd:ignore-start` e `// jscpd:ignore-end`.
- **Periphery (CI) achou código não usado**: apague. Se for usado de um jeito
  que o índice não vê (reflection, só pelo Objective-C runtime), marque a
  declaração com `// periphery:ignore`.
- **Mensagem de commit recusada**: use `tipo(escopo opcional): descrição`, com
  um dos tipos `feat`, `fix`, `refactor`, `test`, `docs`, `style`, `perf`,
  `build`, `ci`, `chore`, `revert`.

Pular os hooks (`git commit --no-verify`) só adia o problema: o CI roda as
mesmas verificações.

## Rodar tudo localmente

```sh
pre-commit run --all-files     # o que um commit roda, em todos os arquivos
Scripts/quality/check          # + build com warnings como erro + Periphery
Scripts/quality/unused-code    # só o Periphery (compila antes)
```

## Gates que rodam os testes

Cobertura, Thread Sanitizer e mutação precisam executar os testes, por isso
ficam só no CI. Para rodar na máquina:

### Cobertura

```sh
swift test --package-path Packages/HarnessKit --enable-code-coverage
Scripts/quality/coverage package

rm -rf build/app.xcresult
xcodebuild test -project Den.xcodeproj -scheme Den -destination 'platform=macOS' \
  -enableCodeCoverage YES -resultBundlePath build/app.xcresult
Scripts/quality/coverage app build/app.xcresult
```

O script compara o que foi medido com `.coverage-floor.json`: um piso por
alvo do HarnessKit e um para o app fora das pastas `Views`, que os testes de
UI exercitam. Abaixo do piso, falha. Depois de aumentar a cobertura, suba o
piso com `--write-floor` e commite o arquivo. Ele grava meio ponto abaixo do
medido, porque a cobertura oscila um pouco de uma execução para outra.

Os pisos valem para o Xcode do CI (`XCODE_VERSION` nos workflows). Com outro
Xcode na máquina a medição pode diferir em alguns décimos, então confira o
número que o job imprime antes de gravar um piso novo.

### Thread Sanitizer

```sh
swift test --package-path Packages/HarnessKit --sanitize=thread
xcodebuild test -project Den.xcodeproj -scheme Den -destination 'platform=macOS' \
  -enableThreadSanitizer YES
```

Uma corrida de dados derruba o comando, e o relatório mostra as duas pilhas
que tocaram a mesma memória. Corrija a corrida; não existe baseline para isso.

### Mutação

```sh
Scripts/quality/mutation --base origin/main   # só as linhas alteradas desde a main
Scripts/quality/mutation --all                # o HarnessKit inteiro, uns 25 minutos
```

O script troca um operador por vez (`==`/`!=`, `<`/`>=`, `>`/`<=`, `&&`/`||`,
`true`/`false`) numa cópia do pacote e roda os testes. Se eles continuam
passando, o mutante sobreviveu: nenhum teste prende aquela linha. O PR falha
quando um sobrevivente não está em `.mutation-baseline.json`.

- **Sobrevivente novo**: escreva o teste que falharia com a troca.
- **Mutante equivalente** (a troca não muda o comportamento): aceite com
  `Scripts/quality/mutation --base origin/main --write-baseline` e commite o
  baseline; o diff mostra o que foi aceito.

O workflow Quality tem um disparo manual que roda o pacote inteiro e publica
o resultado de cada mutante como artefato.

## Dívida registrada (baselines)

Os gates foram ligados num código que já existia. O que já estava lá ficou
registrado e não bloqueia; **qualquer coisa nova bloqueia**.

O baseline do SwiftLint começou com 276 entradas e hoje tem 23: saíram os
comentários (214), os force unwraps e force tries, o `master`/`slave` do PTY,
as closures em posição trailing e a tupla de cinco membros. O que ficou está
descrito abaixo.

| Arquivo | O que guarda |
|---|---|
| `.swiftlint-baseline.json` | o que sobrou da dívida do SwiftLint: funções, tipos e arquivos acima do limite de tamanho e de complexidade (quase tudo no `ChatModel` e no `GitChangesPanel`), as linhas longas que são JSON gravado dos CLIs e um aninhamento que um teste exige |
| `.jscpd-baseline.json` | clones que já existiam (ex.: `ControlChannel` × `ACPChannel`, `ClaudeDiscovery` × `OpenCodeDiscovery`, vários testes) |
| `.periphery-baseline.json` | o que o Periphery acha no app e não dá para apagar: `@State` usado só via `$`, exigência de protocolo que o app ainda não chama, propriedade lida só pelo `Equatable` sintetizado, e `RunInstance.configurationID` |
| `.mutation-baseline.json` | mutantes que já sobreviviam no HarnessKit, casados pelo texto da linha |

Para limites de tamanho, o SwiftLint compara a mensagem inteira (“a função tem
73 linhas”). Então mexer numa função que já estava acima do limite faz ela
aparecer de novo: ou ela volta para dentro do limite, ou você atualiza o
baseline. Depois de corrigir dívida antiga, atualize também, para ela sair do
arquivo:

```sh
Scripts/quality/baseline                       # SwiftLint + jscpd
Scripts/quality/unused-code --write-baseline   # Periphery (precisa do Xcode)
```

e commite os arquivos gerados — o diff mostra exatamente o que entrou ou saiu.

## Atualizar uma ferramenta

- SwiftLint, SwiftFormat, Periphery: troque versão e checksum/commit no topo de
  `Scripts/quality/tool`.
- Hooks do pre-commit (jscpd, gitleaks, shellcheck, actionlint…):
  `pre-commit autoupdate`, e ajuste a versão do jscpd em
  `additional_dependencies` e em `Scripts/quality/baseline`.
- Xcode do CI: troque `XCODE_VERSION` no topo de `.github/workflows/tests.yml`
  e de `.github/workflows/quality.yml`. Com warnings como erro, um compilador
  novo pode pedir correções; faça a troca num PR próprio.

Depois rode `Scripts/quality/check` e commite o que a nova versão pedir.

## Próximos passos sugeridos

Coisas que também dá para verificar estaticamente e que ainda não estão ligadas:

1. **Acessibilidade**: as regras opt-in `accessibility_label_for_image` e
   `accessibility_trait_for_button` do SwiftLint acham hoje 49 imagens sem
   rótulo (ou sem `.accessibilityHidden(true)`, se forem decorativas) e 6 botões
   feitos com `onTapGesture`.
2. **Strings e localização**: `SWIFT_EMIT_LOC_STRINGS` está ligado no app; um
   String Catalog com a verificação de chaves faltando/obsoletas do Xcode pegaria
   textos sem tradução.
3. **Revisão de dependências e licenças** quando o projeto passar a ter pacotes
   de terceiros (hoje não tem): `swift package show-dependencies` +
   verificação de licenças, e Dependabot para as GitHub Actions.
4. **GitHub**: ligar *secret scanning* com *push protection* e exigir os jobs
   `Quality` como status checks obrigatórios na proteção da `main`.
5. **Spell check** de identificadores e comentários com
   [typos](https://github.com/crate-ci/typos), que tem hook de pre-commit.
