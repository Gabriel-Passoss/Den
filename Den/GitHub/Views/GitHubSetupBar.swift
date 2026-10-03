import SwiftUI
import AppKit

struct GitHubSetupBar: View {
    let state: GitHubCLIState
    var choose: () -> Void
    var retry: () -> Void
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "doc.on.doc").font(.system(size: 9))
                    Text("Copiar")
                    Text(command).font(.system(size: 11, design: .monospaced)).foregroundStyle(InlineCode.color)
                }
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .fixedSize()
            if case .missing = state {
                Button(action: choose) {
                    Text("Já tenho, escolher…")
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
            Button("Tentar de novo", action: retry)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(InlineCode.color)
                .fixedSize()
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dispensar")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 34)
        .background(Color.gray.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.gray.opacity(0.3), lineWidth: 1))
    }

    private var message: String {
        if case .notLoggedIn(let host) = state { return "O gh precisa de login em \(host)" }
        return "Instale o GitHub CLI para o Den acompanhar seus PRs"
    }

    private var command: String {
        if case .notLoggedIn = state { return "gh auth login" }
        return "brew install gh"
    }
}
