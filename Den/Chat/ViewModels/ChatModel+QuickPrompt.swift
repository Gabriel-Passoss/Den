import Foundation
import HarnessCore

extension ChatModel {
    var visibleSuggestion: String? {
        guard prompt.isEmpty, pendingAttachments.isEmpty, pendingPastes.isEmpty,
              !isBusy else { return nil }
        return suggestedReply
    }

    func acceptSuggestion() async {
        guard let reply = visibleSuggestion else { return }
        await send(text: reply)
    }

    func dismissSuggestion() {
        suggestionTurn += 1
        suggestedReply = nil
    }

    func turnEnded(_ result: TurnResult) {
        Task { await refreshContextUsage() }
        guard !result.isError else { return }
        suggestReply()
        captureMemory(atLeast: MemoryModel.turnThreshold)
    }

    func generateTitle(from text: String) {
        let instruction = "Gere um título curto (3 a 5 palavras, sem aspas e sem "
            + "ponto final) que resuma o pedido a seguir, na mesma língua dele. "
            + "Responda somente o título.\n\nPedido: \(text.prefix(QuickPrompt.requestLimit))"

        runQuickPrompt(instruction) { [weak self] output in
            guard let title = QuickPrompt.oneLine(output, maxLength: 80) else { return }
            Task { await self?.applyGeneratedTitle(title) }
        }
    }

    private func suggestReply() {
        dismissSuggestion()
        guard pending == nil, pendingQuestion == nil,
              let replyIndex = lines.lastIndex(where: { $0.role == .assistant }),
              let requestIndex = lines.lastIndex(where: { $0.role == .user }),
              requestIndex < replyIndex,
              ReplySuggestion.isAsking(lines[replyIndex].text) else { return }
        let instruction = ReplySuggestion.instruction(
            request: lines[requestIndex].text, reply: lines[replyIndex].text)
        let turn = suggestionTurn
        runQuickPrompt(instruction) { [weak self] output in
            guard let self, turn == suggestionTurn else { return }
            suggestedReply = ReplySuggestion.parse(output)
        }
    }

    private func runQuickPrompt(_ instruction: String,
                                then use: @escaping @MainActor (String) -> Void) {
        guard let installation, let adapter = registry.harness(for: harness),
              let arguments = adapter.quickPromptArguments(for: instruction) else { return }
        let runner = runner
        Task {
            guard let output = try? await runner.run(installation.executable, arguments)
            else { return }
            use(output)
        }
    }
}
