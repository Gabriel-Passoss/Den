import SwiftUI
import AppKit

struct CodeBlock: View {
    let code: String
    let language: String?

    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(MarkdownText.highlighted(code, language: language)) { line in
                Text(line.text)
                    .font(.system(size: 12.5, design: .monospaced))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.terminal, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Theme.border, lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            if hovering { copyButton }
        }
        .onHover { hovering = $0 }
    }

    private var copyButton: some View {
        Button(action: copy) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11))
                .foregroundStyle(copied ? Theme.added : Theme.textSecondary)
                .frame(width: 26, height: 26)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Theme.borderControl, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(6)
        .help("Copiar código")
        .accessibilityLabel("Copiar código")
    }

    private func copy() {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(code, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}
