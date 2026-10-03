import SwiftUI

struct JumpToEndButton: View {
    var isVisible: Bool
    var action: () -> Void

    var body: some View {
        Group {
            if isVisible {
                Button(action: action) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 34, height: 34)
                        .background(Theme.raised, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.borderControl, lineWidth: 1))
                        .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                .help("Ir para o final")
                .accessibilityLabel("Ir para o final")
            }
        }
        .animation(.easeOut(duration: 0.15), value: isVisible)
    }
}
