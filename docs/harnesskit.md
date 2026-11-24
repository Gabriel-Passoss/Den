# HarnessKit

O `Packages/HarnessKit` é a parte do Den que não conhece interface: ele acha o
CLI de um harness, sobe um processo, conversa com ele e normaliza o que volta
num transcript durável. `docs/quality.md` descreve os gates que prendem essa
fronteira (o `headless_harnesskit` barra `import SwiftUI` aqui dentro).

Este documento guarda as decisões que o código não consegue dizer no nome de
um símbolo — por que algo é feito de um jeito e qual bug o outro jeito traz.

## Nenhuma leitura bloqueia uma thread

`CommandRunner.run` sobe o processo e junta a saída por *handlers*: cada pipe
entrega o que leu no `readabilityHandler` e a saída do processo chega no
`terminationHandler`. O `RunCollector` só devolve o resultado quando as três
pontas fecharam — a saída do processo e o fim de cada um dos dois pipes.

A alternativa óbvia seria ler os pipes de forma bloqueante e chamar
`waitUntilExit`. Não dá: a leitura bloqueante pode deixar sem CPU exatamente a
fila que reporta a saída do processo, e o `run` fica pendurado com o processo
já morto há tempo. É um deadlock que só aparece sob carga, que é quando o CI
roda tudo em paralelo.

## O fim do stream carrega o motivo

Quando o CLI morre sem ninguém pedir — status de saída diferente de zero, ou um
sinal que não veio do `terminate()` — o stream não termina de forma limpa: ele
termina com `ProcessTransport.ExitFailure`, que leva o status, o stderr e se
foi sinal.

Isso é deliberado. Se o stream simplesmente acabasse, quem lê não teria como
distinguir "o CLI respondeu tudo" de "o CLI caiu", e um `claude` que morreu por
chave de API inválida pareceria uma conversa que terminou normalmente.

No `ACPChannel`, a mesma ideia vale para as requisições em voo: `markClosed(by:)`
guarda a causa, e tanto as requisições que estavam esperando quanto as mandadas
depois falham com ela, em vez de um `channelClosed` seco que não diz nada sobre
o que aconteceu.

## Formatos desconhecidos não derrubam o transcript

`Handoff` e `TranscriptEntry.Kind` decodificam um discriminador que não
conhecem em `.unrecognized(discriminator:payload:)` e reencodam fiel. É o que
permite um transcript gravado por uma versão do CLI ser lido depois que o
formato mudou, sem perder dado nem quebrar.

Os dois enums têm um `Known` interno com as `CodingKeys` dos casos que
conhecem, e o teste `theOpenEnumsDoNotDivergeFromTheirKnownDiscriminators`
confere que cada caso novo chegou lá — ele localiza os dois enums lendo o
fonte, procurando a abertura de `Kind` e a de `Known` nessa ordem, então essa
estrutura aninhada é exigência de teste, não acidente.
