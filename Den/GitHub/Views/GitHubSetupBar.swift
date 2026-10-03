import SwiftUI
import AppKit

struct GitHubSetupBar: View {
    let state: GitHubCLIState
    var choose: () -> Void
    var retry: () -> Void
    var dismiss: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc").font(.system(size: 10))
                    Text("Copiar")
                    Text(command)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.accentSoft)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .frame(height: 26)
            }
            .buttonStyle(DenButtonStyle(kind: .secondary, radius: 7))
            .fixedSize()
            if case .missing = state {
                Button(action: choose) {
                    Text("Já tenho, escolher…")
                        .font(.system(size: 12))
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                }
                .buttonStyle(DenButtonStyle(kind: .secondary, radius: 7))
                .fixedSize()
            }
            Button(action: retry) {
                Text("Tentar de novo")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accentSoft)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
            }
            .buttonStyle(.denGhost(radius: 7))
            .fixedSize()
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .iconLabel(size: 24)
            }
            .buttonStyle(.denGhost(radius: 6))
            .accessibilityLabel("Dispensar")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 36)
        .foregroundStyle(Theme.text)
        .background(Theme.card, in: shape)
        .overlay(shape.strokeBorder(Theme.borderCard, lineWidth: 1).allowsHitTesting(false))
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
