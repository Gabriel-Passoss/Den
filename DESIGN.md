# DESIGN.md · Den

> Se este arquivo e o código discordarem, o código vale até a pessoa decidir. Registre o conflito em Questões em aberto.

## Product

Den é um app macOS que orquestra harnesses de agentes de código (hoje Claude Code e OpenCode). Ele é um orquestrador, nunca um harness: não implementa loop de agente, gestão de contexto nem execução de ferramenta.

O Den passa a ser organizado por um workflow kanban:

- A visualização principal é o board.
- Colunas: **Backlog, Especificação, Aguardando, Em andamento, Testes, Padrões e PR**.
- Cada etapa do kanban tem um agente responsável, com contexto específico configurável.
- Mover um card para uma etapa dispara o agente dela automaticamente.
- **Aguardando** é onde o card espera por mim. É o ponto de maior atenção do board e não tem agente.
- Issues do Jira atribuídas ao usuário viram cards no Den. Por enquanto, o Den só lê o Jira.
- O card passa por grill-me-with-docs, depois pela especificação, e pode virar sub-tasks.
- As sub-tasks ficam englobadas pelo card principal vindo do Jira e existem só no Den, sem ticket próprio. Cada tarefa tem o próprio worktree e, por enquanto, as sub-tasks usam o chat do card pai.
- A sidebar segue esta ordem: seletor de projeto na linha dos botões da janela, busca, Início (o board), Agentes e tasks alocadas com acesso ao chat.
- O botão Agentes abre uma tela com a lista dos agentes existentes, onde cada um tem seus contextos e as skills que pode carregar.

**Trabalho principal do board:** ver o que precisa de mim, agir e voltar ao que eu estava fazendo.

## Audience and voice

Um único desenvolvedor, o próprio autor, usando o app localmente no Mac. Sem contas, sem time e sem responsáveis humanos nos cards.

Interface em português do Brasil, com texto curto e direto, como já acontece no app ("Nova conversa", "Nenhuma conversa aberta"). Termos técnicos ficam como o desenvolvedor os usa: worktree, diff, PR, harness.

## Mood

Palavras: **calmo e vivo** em primeiro lugar, sem abrir mão de **preciso e denso**.

Na prática: os agentes trabalham em segundo plano com sinais discretos de vida, e só o que precisa de mim chama atenção.

Nunca parecer: um clone do Jira, um dashboard SaaS, um terminal ou log cru.

## Brand

Design system source: `Den/Shared/Theme/Theme.swift`; the Penpot guide mirrors it (página `Guide`, set `Theme`). O registro da sincronização está em `design-sync.json`.

No Penpot, a fonte do sistema (SF Pro) é substituída por Inter. Isso vale só para o desenho.

- 42 tokens de cor: superfícies, bordas, texto, accent, estados de diff, alerta e pets.
- Escalas em pontos: tipografia (`font10` a `font24`), espaçamento (`space2` a `space24`) e raio (`radius4` a `radius16`).
- Acento índigo (`accent` `#8B93FF`, `action` `#6E78F7`) sobre neutros escuros (`canvas` `#0F1115`).
- Componentes base: `DenButtonStyle` (primary, secondary, ghost), `PillLabel`, `ChipLabel`, `IconLabel`, `ChipSurface`, `DenMenu`.
- Fonte do sistema e SF Symbols, como já usados nas views.
- `waiting` e os tokens de alerta já existem e são candidatos naturais ao sinal de "precisa de mim" (assumed).

## References

- **Linear** — pegar: cor só como sinal, card enxuto com ID curto (a chave do Jira), sub-issues agrupadas no card pai com progresso resumido. Evitar: contraste muito baixo, recursos de time, muitas views e filtros.
- **Sidebar de referência enviada pelo autor** — pegar: seletor ao lado dos botões da janela, busca logo abaixo e navegação simples com seções. Evitar: tema claro e rodapé de conta, porque o Den é escuro e sem contas (assumed).

- **Painel de agente enviado pelo autor** — pegar: avatar no topo, nome, "o que faz" e configurações em grupos de linhas com valor resumido e seta.

## Constraints

- macOS 26.6 ou superior, SwiftUI, janela mínima de 860×560.
- O board usa rolagem horizontal quando as sete colunas não couberem na janela.
- Somente tema escuro, como o app força hoje.
- Ícones em SF Symbols.
- Movimento: um indicador pequeno e contínuo só nos cards em execução, e transições curtas ao mudar de coluna. Respeitar Reduzir Movimento.
- Status legível de relance, nunca apenas por cor.
- O que varia por harness deve vir de `HarnessCapabilities`: a UI oculta o que o harness não suporta.

## Decisions log

- 2026-11-23 — O board vira a visualização principal e a sidebar lista as tasks com acesso ao chat — pedido do autor para reorganizar o Den em torno de um workflow de agentes.
- 2026-11-23 — O board prioriza "o que precisa de mim" — é o trabalho principal ao abri-lo.
- 2026-11-23 — Uso individual e local — elimina recursos de time, contas e sincronização entre pessoas.
- 2026-11-23 — Issue do Jira é o card pai, e as sub-tasks ficam agrupadas nele — mantém a origem do trabalho visível durante todo o processo.
- 2026-11-23 — Animação contínua só em cards ativos — equilibra calmo e vivo.
- 2026-11-23 — Sete colunas: Backlog, Especificação, Aguardando, Em andamento, Testes, Padrões e PR — definição inicial do autor.
- 2026-11-23 — Mover um card dispara o agente da etapa sozinho — a atenção do autor fica para o que realmente precisa dele.
- 2026-11-23 — Integração com o Jira somente leitura — escopo inicial.
- 2026-11-23 — Sub-tasks usam o chat do card pai — escopo inicial.
- 2026-11-23 — Cada tarefa, incluindo sub-tasks, tem worktree próprio — evita agentes editando os mesmos arquivos ao mesmo tempo.
- 2026-11-23 — Board com rolagem horizontal — mantém as sete colunas legíveis na janela mínima.
- 2026-11-23 — Aguardando é a coluna de espera pelo autor — concentra o trabalho principal do board, ver o que precisa de mim.
- 2026-11-23 — Design system importado para o Penpot, com a UI redesenhada a partir das referências — o board nasce das peças do app, sem herdar o layout atual.
- 2026-11-23 — Pedido de permissão ou pergunta no meio de uma etapa mantém o card na coluna, com o sinal "precisa de mim" — preserva onde o trabalho parou.
- 2026-11-23 — Contador fixo no topo leva aos itens que precisam de mim — Aguardando pode sair da área visível na rolagem horizontal.
- 2026-11-23 — Mover um card mostra "Desfazer" por 5 segundos antes de o agente iniciar — evita gastar tokens ou mexer em um worktree por arraste acidental.
- 2026-11-23 — Cada sub-task trabalha no próprio worktree e é integrada na branch do card pai, que abre um único PR ligado à issue do Jira — mantém uma entrega por issue.
- 2026-11-23 — Sub-tasks não têm ticket nem chave do Jira — elas nascem da especificação e existem só no Den.
- 2026-11-23 — Colunas com fundo próprio: canvas, coluna em `sidebar` e card em `raised` — dá profundidade ao board sem criar cores novas.
- 2026-11-23 — Sidebar com seletor de projeto, busca, Início, Agentes e tasks — concentra contexto, navegação e configuração em um só lugar, com Agentes logo abaixo de Início a pedido do autor.
- 2026-11-23 — Agentes são pets no estilo "objeto vivo": o instrumento da etapa vira o bicho (folha, capacete, frasco, esquadro e carta), e os olhos mostram o status — escolha do autor para deixar os agentes mais amigáveis e legíveis em tamanho pequeno.
- 2026-11-23 — Agentes vira um botão abaixo de Início, com tela própria para contextos e skills — substitui a lista fixa na sidebar e dá espaço para a configuração.
- 2026-11-23 — Peças novas só no Penpot, ainda sem código: StatusIndicator, AttentionCounter, ColumnHeader, TaskCard, SubtaskRow, SidebarTaskRow, SidebarSearch, SidebarNavRow, ProjectSelector, AgentPet, AgentListRow, SettingRow e TextField — criadas para o board e a tela de Agentes.
- 2026-11-23 — Alterações em um agente em execução valem a partir da próxima execução — não muda as regras no meio de uma tarefa.
- 2026-11-23 — Por enquanto há um agente por etapa, sem criar ou excluir agentes — mantém a tela focada em contextos e skills.
- 2026-11-23 — Estados de partes da tela ficam em folhas (`1.8 · Board` e `2.3 · Agentes`), e só o que muda a tela inteira ganha board próprio — facilita comparar e implementar.
- 2026-11-23 — Mudanças no Jira e falhas de um item aparecem no próprio card, com a ação que resolve — um problema de uma task não deve interromper o board inteiro.
- 2026-11-23 — Tasks na sidebar mostram o pet do agente em 32 px, com o humor do status e a bolinha à direita — o agente fica reconhecível sem abrir a task.
- 2026-11-23 — Clicar em uma task, na sidebar ou no board, abre a tela da tarefa com chat ao centro e painel à direita com agente, Resumo, Sub-tasks e Histórico — segue o padrão do painel de agente e mantém a conversa como foco.
- 2026-11-23 — O chat da tarefa reaproveita o chat implementado (`AssistantTurn`, `MessageBubble`, `ToolSteps`, `ThinkingRow`, `QuestionCard`, `PermissionCard` e `ChatComposer`), trocando o `HarnessBadge` pelo pet do agente — pedido do autor para não reinventar o que já funciona.
- 2026-11-23 — Cada task tem um chat contínuo com divisores por etapa, e a sub-task abre o chat do pai com destaque no painel — mantém o raciocínio da task em um só lugar.
- 2026-11-23 — Mensagem enviada durante a execução entra na fila, e parar continua disponível quando o harness permite — o autor pode orientar o agente sem perder o trabalho em andamento.
- 2026-11-23 — Responder a uma decisão mantém o card na coluna e o agente continua de onde parou — preserva o ponto em que o trabalho estava.
- 2026-11-23 — Na janela mínima, o painel da tarefa recolhe e abre por um botão no topo — em 860 px o chat precisa da largura disponível.
- 2026-11-23 — Design do board, da tela de Agentes e da tela da tarefa aprovado pelo autor no arquivo `Den` do Penpot — libera o planejamento da implementação em SwiftUI.
- 2026-11-23 — Import no Penpot: 39 tokens e DenButtonStyle, ChipSurface + ChipLabel, HarnessBadge e DenMenuList desenhados; os outros 9 componentes ficam só no código — são as peças que board, sidebar e chat mais usam.
- 2026-11-23 — Sub-tasks acompanham o card pai e não andam sozinhas pelas colunas — decisão do autor.
- 2026-11-23 — O contexto do agente é por task, e a orquestração fornece somente o necessário para a tarefa, conforme a configuração do agente — decisão do autor.
- 2026-11-23 — Por enquanto, cada etapa usa o harness e o modelo padrão do seu agente — decisão do autor.
- 2026-11-23 — Por enquanto, o Den não terá conversas livres — decisão do autor.
- 2026-11-23 — O grilling acontece em Especificação, e Backlog não tem agente nem dispara nada — confirmado pelo autor.
- 2026-11-23 — As cinco cores dos pets entram em `Theme.swift` com os valores do Penpot — o board e a tela de Agentes passam a ter uma fonte única.
- 2026-11-23 — `textFaint` passa de `#555C6C` para `#767D90`, com 4,6:1 sobre `canvas` — ele já é usado em estados e metadados, que precisam ser legíveis.
- 2026-11-23 — Tipografia, espaçamento e raio ganham escalas a partir dos valores mais usados no código — as views atuais migram aos poucos, durante o redesenho.
- 2026-11-23 — O foco de `DenButtonStyle` é um contorno interno de 2 pt em `accentSoft`, com o raio do botão — segue o estado desenhado no Penpot.
- 2026-11-24 — Etapas definidas pelo usuário: cada projeto tem um board que começa vazio, e o usuário cria as etapas e vincula a cada uma um agente seu, ou nenhum — substitui as entradas "Sete colunas" e "um agente por etapa, sem criar ou excluir agentes". Ver `docs/adr/0001-etapas-definidas-pelo-usuario.md`.
- 2026-11-24 — Agentes são criados pelo usuário, e o mesmo agente pode atender mais de uma etapa — decisão do autor (#31).
- 2026-11-24 — "Precisa de mim" é derivado só das pendências da task (decisão pedida pelo agente ou problema), e não de uma etapa — sem etapas fixas, não existe uma Aguardando para o domínio reconhecer.
- 2026-11-24 — Uma etapa marcada como final conclui as tasks que estão nela — o usuário monta a própria coluna de conclusão.
- 2026-11-24 — A task pode ser criada no Den, e o Jira passa a ser uma das integrações possíveis com apps de tarefas externos — o M1 roda o workflow inteiro sem integração.
- 2026-11-24 — Subagentes são execuções que o Den abre, uma por sub-task e no worktree dela, a pedido do agente principal. Não são os subagentes internos do harness — assim o Den continua orquestrando e consegue mostrar cada sub-task. O agente de qualquer etapa pode criar sub-tasks, e eu não as crio à mão no M1.
- 2026-11-24 — Sub-tasks têm progresso próprio (pendente, em andamento, concluída) e nenhuma etapa. Quem muda o progresso é o agente que orquestra as sub-tasks, e mover a task pai não o altera — o card mostra quantas sub-tasks estão concluídas.
- 2026-11-24 — O movimento manual é livre entre etapas, para frente, para trás ou pulando etapas — a ordem sugere a próxima etapa, mas não proíbe nenhuma.
- 2026-11-24 — Uma etapa com tasks não pode ser excluída, criar uma task exige uma etapa (o board pode voltar a ficar vazio quando a última etapa vazia é excluída), reordenar etapas não move tasks e uma task nova entra na primeira etapa — regras de edição do board.
- 2026-11-24 — O domínio do workflow fica num target próprio do `HarnessKit`, sem dependência de `HarnessCore` — o board não precisa saber o que é um harness.
- 2026-11-24 — Cada agente tem um encaminhamento: a instrução de para onde a task segue quando ele considera a etapa concluída. Ele pode mover a task para outra etapa do board ou devolvê-la para mim — o fluxo entre etapas é decidido pelos agentes, não fixado no domínio.
- 2026-11-24 — Todo movimento feito por agente leva uma passagem para quem continua. Quando eu movo a task para uma etapa com agente, o agente da etapa de origem é acionado para escrever a passagem — o próximo agente recebe só o contexto que importa. "Passagem" se distingue do `Handoff.briefing` do HarnessKit, que é da troca de harness.
- 2026-11-24 — Entrar numa etapa com agente dispara esse agente, não importa quem moveu a task. Depois de N movimentos seguidos de agentes sem ação minha (limite de encadeamento, padrão 5, configurável nas preferências do app), o próximo movimento vira pendência — evita ciclos que gastam tokens.
- 2026-11-24 — Agente sem encaminhamento, ou que não decidiu nada, deixa a task na etapa com a pendência "etapa concluída" — "precisa de mim" só vem de pendências.
- 2026-11-24 — O histórico da task registra cada movimento com autor, origem, destino e horário. O Desfazer vale só para movimentos meus — um movimento de agente é revertido movendo a task à mão.
- 2026-11-24 — A task tem uma execução (nenhuma, executando, terminada), e movê-la à mão encerra a execução em andamento quando o Desfazer expira.
- 2026-11-24 — Uma decisão fecha quando é respondida ou vira "não vale mais". Pendências de etapa concluída, de limite de encadeamento e de devolução fecham quando movo a task ou disparo o agente de novo. Problemas fecham pela ação que os resolve.
- 2026-11-24 — Um agente não pode mover uma task para uma etapa final com sub-tasks abertas, e a tentativa vira pendência. Eu posso.
- 2026-11-24 — Na passagem manual: sem agente na origem não há passagem, e sem agente no destino ela não é pedida. A ordem é Desfazer, encerrar a execução da origem, escrever a passagem e disparar o destino. Se a passagem falhar, a task ganha uma pendência com "tentar de novo" e "seguir sem passagem". Qualquer ação minha na task zera o limite de encadeamento.
- 2026-11-24 — Dentro de uma etapa, a ordem das tasks é automática: as que precisam de mim primeiro, depois as que entraram há mais tempo — sem ordem manual para guardar.
- 2026-11-24 — Uma task pode ser excluída com confirmação, o que encerra as execuções dela e das sub-tasks e apaga o histórico.
- 2026-11-24 — O subagente roda com a configuração do agente principal (contextos, skills, harness e modelo) e recebe a sub-task como pedido. Quando a task pai sai da etapa, as execuções dos subagentes são encerradas junto com a do agente principal, e o progresso fica como estava — o agente da nova etapa pode retomá-lo.
- 2026-11-26 — O movimento manual só vale quando a janela de Desfazer fecha: até lá a task continua na etapa de origem no domínio, com a execução rodando, e só aparece no destino. Desfazer apenas descarta o movimento, que nunca entra no histórico — segue a ordem "Desfazer, encerrar a execução, passagem, disparo". Ver `docs/adr/0002-movimento-vale-quando-o-desfazer-fecha.md` (#35).
- 2026-11-26 — Há uma janela de Desfazer por vez. Mover outra task conclui na hora o movimento que estava aberto; mover a mesma task de novo mantém a origem e reinicia os 5 segundos, e devolvê-la à origem cancela o movimento — um só "Desfazer" na tela, sem fila de toasts (#35).
- 2026-11-26 — A janela é [0, 5) segundos: aos 5 segundos exatos o movimento já não pode ser desfeito. O movimento é registrado com o horário do arraste, que é quando a task entrou na etapa e a posição em que o card já estava (#35).
- 2026-11-26 — Se a task for excluída durante a janela, o movimento cai. Se um agente a mover nesse meio tempo, o meu movimento ainda vale ao fechar a janela, a partir de onde ela estiver — a minha intenção é a mais recente (#35).
- 2026-11-26 — A alternativa acessível ao arraste é o menu "Mover para" no card (clique secundário e ações do VoiceOver), que segue o mesmo caminho do arraste. ⌘Z desfaz enquanto a janela está aberta, e o aviso "Desfazer" é anunciado pelo VoiceOver (#35).
- 2026-11-26 — Fechar o app com a janela aberta conclui o movimento, porque o arraste já expressou a decisão (#35).

## Open questions

- `grill-me-with-docs` é uma skill já existente? Onde ela fica?
- O Penpot ainda precisa receber o novo `textFaint`, as escalas e `focusRingWidth`, listados em `pendingInPenpot` no `design-sync.json`.
- Na implementação, a fila de mensagens e os estados "enviando", "respondida" e "não vale mais" da decisão precisam ser adicionados ao chat atual, porque ainda não existem no código.
- As peças do chat estão desenhadas nas telas 3.x a partir dos valores do código, mas ainda não são componentes da biblioteca do Penpot. Vale registrá-las no guia?
- Só uma referência foi indicada (Linear). Vale acrescentar uma referência de app nativo de Mac?
