import SwiftUI

struct TransientCards: View {
    let chat: ChatModel
    var stickToBottom: () -> Void

    var body: some View {
        if chat.pending != nil || chat.pendingQuestion != nil {
            VStack(spacing: 8) {
                if let pending = chat.pending {
                    PermissionCard(request: pending,
                                   harnessName: chat.harnessName) { option in
                        Task { await chat.resolve(option) }
                    }
                }
                if let question = chat.pendingQuestion {
                    QuestionCard(
                        prompt: question,
                        answer: { selections in
                            stickToBottom()
                            Task { await chat.answerQuestion(selections) }
                        },
                        dismiss: { Task { await chat.dismissQuestion() } }
                    )
                    .id(question.id)
                }
            }
            .aboveComposer(fade: 0.12)
        }
    }
}
