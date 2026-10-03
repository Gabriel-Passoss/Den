import SwiftUI

struct SessionWelcome: View {
    let chat: ChatModel

    var body: some View {
        VStack(spacing: 18) {
            HarnessBadge(harness: chat.harness, size: 40)
            VStack(spacing: 5) {
                Text("\(chat.harnessName) em \(chat.workingDirectory.lastPathComponent)")
                    .font(.system(size: 17, weight: .semibold))
                Text("Descreva o que quer mudar. O agente lê, edita e executa no projeto.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 8) {
                hint(Text("@").font(.system(size: 12, weight: .semibold, design: .monospaced)),
                     "cita arquivos")
                hint(Text("/").font(.system(size: 12, weight: .semibold, design: .monospaced)),
                     "abre comandos")
                hint(Image(systemName: "paperclip").font(.system(size: 11, weight: .medium)),
                     "anexa imagens e PDFs")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    private func hint(_ glyph: some View, _ text: String) -> some View {
        HStack(spacing: 6) {
            glyph
                .foregroundStyle(Theme.accent)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Theme.raised, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
    }
}
