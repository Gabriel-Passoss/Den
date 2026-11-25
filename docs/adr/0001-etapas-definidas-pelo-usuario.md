# Etapas e agentes definidos pelo usuário

O design original fixava sete etapas (Backlog, Especificação, Aguardando, Em andamento, Testes, Padrões e PR), cada uma com um agente próprio que não podia ser criado nem excluído. Decidimos que cada projeto tem um board que começa vazio, e que o usuário cria as etapas e os agentes e vincula no máximo um agente a cada etapa, ou nenhum. O Den deixa de ter opinião sobre o fluxo: o mesmo app atende fluxos diferentes, e "Aguardando" e "PR" passam a ser etapas como quaisquer outras.

## Consequences

- O domínio não conhece nenhuma etapa pelo nome. Tudo o que antes dependia de uma etapa específica vira uma propriedade configurável: a marca **final** e o agente vinculado.
- "Precisa de mim" vem só das pendências, porque nenhuma etapa significa "espera por mim".
- Os pets que nasciam do instrumento de cada etapa fixa precisam de outra regra de identidade.
