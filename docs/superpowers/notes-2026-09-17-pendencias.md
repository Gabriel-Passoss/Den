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
