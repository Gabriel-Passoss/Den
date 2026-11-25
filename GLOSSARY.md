# Den

Den é um app macOS que orquestra harnesses de agentes de código a partir de um board kanban montado pelo próprio usuário. Ele orquestra, nunca implementa um harness.

## Workflow

**Task** (`Task`):
Uma unidade de trabalho que atravessa o workflow, criada no Den ou trazida de uma integração externa.
_Avoid_: card (é só como a task aparece no board), tarefa, ticket, issue

**Sub-task**:
Uma parte de uma task, criada pelo agente que está com ela, que existe só no Den e acompanha a task pai sem ter etapa própria.
_Avoid_: task filha, sub-card

**Subagente**:
Uma execução que o Den abre para uma sub-task a pedido do agente principal, no worktree da própria sub-task.
_Avoid_: subagente do harness (é outra coisa, que o Den não enxerga), worker

**Agente principal**:
O agente da etapa onde a task pai está, que cria as sub-tasks, dispara os subagentes e muda o progresso de cada uma.
_Avoid_: agente pai, orquestrador (o orquestrador é o Den)

**Board**:
O kanban de um projeto, formado pelas etapas que o usuário criou. Cada projeto tem um board.
_Avoid_: kanban, quadro

**Etapa** (`Stage`):
Uma fase do board criada pelo usuário, que pode ter um agente vinculado ou nenhum.
_Avoid_: coluna (é só como a etapa aparece no board), fase, status

**Etapa final**:
Uma etapa marcada pelo usuário como fim do workflow. Toda task que está nela está concluída.
_Avoid_: coluna de concluído, done

**Agente**:
Um agente criado pelo usuário, com contextos e skills próprios, que pode ser vinculado a uma ou mais etapas.
_Avoid_: bot, assistente, harness (o harness é o que executa o agente)

**Encaminhamento**:
A instrução de um agente sobre para onde a task segue quando ele considera a etapa concluída: para outra etapa do board ou de volta para o usuário.
_Avoid_: workflow (é o processo do board inteiro), roteamento, próxima etapa

**Movimento**:
A ida de uma task de uma etapa para outra, feita pelo usuário ou por um agente, e registrada no histórico da task.
_Avoid_: transição, mudança de status

**Passagem**:
O que um agente escreve ao entregar uma task: o que fez e o que importa para quem continua, seja o agente da próxima etapa ou o usuário.
_Avoid_: briefing e handoff (são da troca de harness dentro de uma conversa), resumo

**Limite de encadeamento**:
Quantos movimentos seguidos os agentes podem fazer numa task sem nenhuma ação do usuário antes que o próximo vire uma pendência.
_Avoid_: limite de ciclo, max hops

**Execução**:
O trabalho de um agente sobre uma task ou sub-task: nenhuma, executando ou terminada.
_Avoid_: run, sessão, job

**Progresso**:
O avanço de uma sub-task: pendente, em andamento ou concluída. Quem o muda é o agente que orquestra as sub-tasks.
_Avoid_: andamento, status, etapa (sub-tasks não têm etapa)

**Origem**:
De onde uma task veio: criada no Den ou importada de um app de tarefas externo, como o Jira.
_Avoid_: fonte, provider

**Pendência**:
Algo aberto em uma task que só o usuário resolve: uma decisão pedida pelo agente (permissão ou pergunta) ou um problema (falha, mudança na origem).
_Avoid_: alerta, bloqueio

**Precisa de mim**:
O sinal de que uma task espera pelo usuário. Ele existe enquanto a task tem uma pendência aberta e nunca é marcado à mão.
_Avoid_: atenção, flag, urgente
