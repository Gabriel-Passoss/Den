import SwiftUI

struct ComposerField: View {
    @Bindable var chat: ChatModel
    @Binding var focusRequested: Bool
    let placeholder: String
    var submit: () -> Void
    var stickToBottom: () -> Void

    var body: some View {
        ComposerTextView(text: $chat.prompt, focusRequested: $focusRequested,
                         accessibilityPlaceholder: placeholder,
                         ghost: chat.visibleSuggestion ?? "",
                         onSubmit: submit,
                         onPaste: { chat.capturePaste($0) },
                         onAcceptGhost: acceptSuggestion,
                         onDismissGhost: chat.dismissSuggestion)
            .overlay(alignment: .topLeading) {
                if let suggestion = chat.visibleSuggestion {
                    suggestedReply(suggestion)
                        .transition(.opacity)
                } else if chat.prompt.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textTertiary)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.2), value: chat.visibleSuggestion)
    }

    private func suggestedReply(_ suggestion: String) -> some View {
        Text(suggestion)
            .font(Font(ComposerTextView.font))
            .foregroundStyle(Theme.textTertiary)
            .lineLimit(ComposerTextView.ghostMaxLines)
            .padding(.trailing, ComposerTextView.ghostTrailing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
            .accessibilityLabel("Resposta sugerida: \(suggestion). Seta para a direita envia.")
            .accessibilityIdentifier("suggested-reply")
            .overlay(alignment: .topTrailing) {
                Button(action: acceptSuggestion) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .iconLabel(size: 20)
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Theme.borderStrong, lineWidth: 1))
                }
                .buttonStyle(.denGhost(radius: 5))
                .help("Enviar resposta sugerida (→)")
                .accessibilityLabel("Enviar resposta sugerida")
            }
    }

    private func acceptSuggestion() {
        stickToBottom()
        Task { await chat.acceptSuggestion() }
    }
}
