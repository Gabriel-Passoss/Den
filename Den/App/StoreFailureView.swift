import SwiftUI

struct StoreFailureView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("O Den não conseguiu abrir os seus dados")
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Button { NSApplication.shared.terminate(nil) } label: {
                Text("Encerrar").pillLabel()
            }
            .buttonStyle(.denPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .frame(minWidth: 860, minHeight: 560)
    }
}
