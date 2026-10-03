# Quality gates estáticos

Verificações que olham o código sem executá-lo. Rodam em cada commit (via
[pre-commit](https://pre-commit.com)) e de novo no CI em todo pull request
(`.github/workflows/quality.yml`), com as mesmas versões das ferramentas.

## O que é verificado

| Gate | Ferramenta | Commit | CI |
|---|---|:-:|:-:|
| Formatação Swift (o estilo da casa, sem reescrever o que já é deliberado) | SwiftFormat 0.63.1 — `.swiftformat` | ✓ corrige sozinho | ✓ |
| Lint: falhas lógicas (`a == a`, force unwrap, `Task` que engole erro, observer descartado, `super` esquecido…), idiomas e limites de tamanho | SwiftLint 0.65.1 — `.swiftlint.yml` | ✓ | ✓ |
| Código duplicado (clone novo de ≥ 50 tokens e ≥ 5 linhas) | jscpd 5.4.0 — `.jscpd.json` | ✓ | ✓ |
| Warnings do compilador viram erro (concorrência, deprecações, valores não usados, código inalcançável) | `swiftc` / `xcodebuild` — `Scripts/quality/build-strict` | | ✓ |
| Código não usado: declarações, parâmetros, imports, propriedades só atribuídas | Periphery 3.8.0 — `.periphery.yml` e `Packages/HarnessKit/.periphery.yml` | | ✓ |
| Segredos (chaves, tokens) | gitleaks 8.30.1 | ✓ no que está staged | ✓ no histórico inteiro |
| Mensagem de commit no formato Conventional Commits (`feat(app): …`) | conventional-pre-commit | ✓ | ✓ nos commits do PR |
| Scripts shell | shellcheck | ✓ | ✓ |
| Workflows do GitHub Actions (inclui shellcheck nos `run:`) | actionlint | ✓ | ✓ |
| Higiene: conflito de merge esquecido, nomes que colidem no APFS, arquivo grande, JSON/YAML/plist inválido, chave privada, espaço no fim da linha, LF | pre-commit-hooks | ✓ | ✓ |

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

## No dia a dia

- **SwiftFormat mexeu no arquivo**: o commit para, o arquivo fica corrigido;
  confira com `git diff`, rode `git add` e commite de novo.
- **SwiftLint reclamou**: a mensagem diz a regra entre parênteses. Corrija; se
  for falso positivo de verdade, desligue só ali, explicando o motivo:
  `// swiftlint:disable:next force_unwrapping — o sufixo é uma constante`.
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

## Dívida registrada (baselines)

Os gates foram ligados num código que já existia. O que já estava lá ficou
registrado e não bloqueia; **qualquer coisa nova bloqueia**:

| Arquivo | O que guarda |
|---|---|
| `.swiftlint-baseline.json` | violações do SwiftLint que já existiam (funções e arquivos longos, force unwraps, `master`/`slave` no PTY…) |
| `.jscpd-baseline.json` | clones que já existiam (ex.: `ControlChannel` × `ACPChannel`, `ClaudeDiscovery` × `OpenCodeDiscovery`, vários testes) |
| `.periphery-baseline.json` | o que o Periphery acha no app e não dá para apagar: `@State` usado só via `$`, exigência de protocolo que o app ainda não chama, propriedade lida só pelo `Equatable` sintetizado, e `RunInstance.configurationID` |

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

Depois rode `Scripts/quality/check` e commite o que a nova versão pedir.

## Próximos passos sugeridos

Coisas que também dá para verificar estaticamente e que ainda não estão ligadas:

1. **Swift 6 language mode no app** (`SWIFT_VERSION = 6`). O pacote já usa; no
   app, o modo 5 ainda deixa passar como warning corridas de dados que o modo 6
   transforma em erro — os 7 warnings corrigidos agora eram desse tipo.
2. **Acessibilidade**: as regras opt-in `accessibility_label_for_image` e
   `accessibility_trait_for_button` do SwiftLint acham hoje 49 imagens sem
   rótulo (ou sem `.accessibilityHidden(true)`, se forem decorativas) e 6 botões
   feitos com `onTapGesture`.
3. **Regras de arquitetura** como `custom_rules` do SwiftLint, no espírito do
   `ModuleBoundaryTests`: por exemplo, proibir `import SwiftUI`/`AppKit` dentro
   de `Packages/HarnessKit` e `import ClaudeHarness` em `HarnessCore`.
4. **Strings e localização**: `SWIFT_EMIT_LOC_STRINGS` está ligado no app; um
   String Catalog com a verificação de chaves faltando/obsoletas do Xcode pegaria
   textos sem tradução.
5. **Revisão de dependências e licenças** quando o projeto passar a ter pacotes
   de terceiros (hoje não tem): `swift package show-dependencies` +
   verificação de licenças, e Dependabot para as GitHub Actions.
6. **GitHub**: ligar *secret scanning* com *push protection* e exigir os jobs
   `Quality` como status checks obrigatórios na proteção da `main`.
7. **Cobertura de testes como gate** (não é estática, mas é barata): o
   `xcodebuild test` já pode gerar cobertura com `-enableCodeCoverage YES`, e o
   CI falharia se ela caísse.
8. **Spell check** de identificadores e comentários com
   [typos](https://github.com/crate-ci/typos), que tem hook de pre-commit.
