# O movimento manual só vale quando a janela de Desfazer fecha

Mover uma task mostra "Desfazer" por 5 segundos antes de o agente iniciar. Havia duas formas de modelar isso: aplicar o movimento no board na hora e revertê-lo no Desfazer, ou manter o movimento fora do board até a janela fechar. Decidimos pela segunda. O board guarda só movimentos que valeram, e a janela de Desfazer (`UndoWindow`) guarda o movimento aberto, que a tela usa para mostrar o card no destino. Quando a janela fecha, o movimento é aplicado com o horário do arraste.

Aplicar e reverter exigiria desfazer efeitos que `moveTask` já produz: encerrar a execução, fechar pendências e zerar o limite de encadeamento. Também deixaria no histórico um movimento que não aconteceu, ou exigiria apagá-lo. E o design pede que a execução da origem só seja encerrada quando o Desfazer expira.

## Consequences

- Durante a janela, a task continua na etapa de origem para o domínio e para a persistência, e a execução da origem segue rodando. Só a exibição (`tasks(in:showing:)`) a coloca no destino.
- Desfazer não toca o board: só descarta o movimento aberto. O histórico nunca tem movimentos desfeitos.
- A janela não é persistida. Por isso fechar o app com ela aberta precisa concluir o movimento antes de sair.
- Quem controla o tempo é o app. O domínio só compara horários, o que permite testar os 5 segundos sem relógio.
