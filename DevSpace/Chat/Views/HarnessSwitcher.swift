import SwiftUI
import HarnessCore

struct HarnessSwitcher: View {
    let chat: ChatModel

    var body: some View {
        Menu {
            ForEach(HarnessRegistry.all.map(\.id), id: \.rawValue) { candidate in
                Button {
                    Task { await chat.switchHarness(to: candidate) }
                } label: {
                    Label {
                        Text(HarnessBadge.name(for: candidate))
                    } icon: {
                        HarnessBadge(harness: candidate, size: 14)
                    }
                }
                .disabled(candidate == chat.harness)
            }
        } label: {
            HStack(spacing: 6) {
                HarnessBadge(harness: chat.harness, size: 15)
                Text(chat.harnessName)
            }
            .padding(.horizontal, 6)
        }
        .labelStyle(.titleAndIcon)
        .disabled(!chat.canSwitchHarness)
        .help(chat.isBusy
              ? "Espere o turno terminar para trocar de harness"
              : "Trocar de harness levando a conversa junto")
    }

}
