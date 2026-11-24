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

- 37 tokens de cor: superfícies, bordas, texto, accent, estados de diff e alerta.
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

## Open questions

- `grill-me-with-docs` é uma skill já existente? Onde ela fica?
- `textFaint` (`#555C6C`) tem contraste de cerca de 2,8:1 sobre `canvas`. Ele não deve ser usado para estado ou metadado no board, e pode precisar de ajuste.
- O estado de foco de `DenButtonStyle` está desenhado como proposto e ainda não existe no código.
- O código não tem tokens de tipografia, espaçamento e raio. O redesenho deve propor uma escala?
- As cinco cores dos pets (`petSpec`, `petImpl`, `petTest`, `petStd`, `petPr`) estão propostas no Penpot e ainda precisam entrar em `Theme.swift` por um export aprovado.
- Na implementação, a fila de mensagens e os estados "enviando", "respondida" e "não vale mais" da decisão precisam ser adicionados ao chat atual, porque ainda não existem no código.
- As peças do chat estão desenhadas nas telas 3.x a partir dos valores do código, mas ainda não são componentes da biblioteca do Penpot. Vale registrá-las no guia?
- Só uma referência foi indicada (Linear). Vale acrescentar uma referência de app nativo de Mac?
