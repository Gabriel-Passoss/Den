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
                    .font(.system(size: 12, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .topTrailing) {
            if hovering { copyButton }
        }
        .onHover { hovering = $0 }
    }

    private var copyButton: some View {
        Button(action: copy) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11))
                .foregroundStyle(copied ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                .frame(width: 22, height: 22)
                .background(.background.opacity(0.85),
                            in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.quaternary, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(5)
        .help("Copiar código")
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
