import SwiftUI
import HarnessCore

struct HarnessSwitcher: View {
    let chat: ChatModel

    var body: some View {
        MenuChip(bordered: true, radius: 10) {
            Section("Harness desta sessão") {
                ForEach(chat.availableHarnesses, id: \.rawValue) { candidate in
                    Button {
                        Task { await chat.switchHarness(to: candidate) }
                    } label: {
                        Label {
                            Text(HarnessBadge.name(for: candidate))
                        } icon: {
                            HarnessBadge.menuIcon(for: candidate)
                        }
                    }
                    .disabled(candidate == chat.harness)
                }
            }
        } label: {
            HStack(spacing: 8) {
                HarnessBadge(harness: chat.harness, size: 20)
                Text(chat.harnessName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Chevron()
            }
            .padding(.leading, 7)
            .padding(.trailing, 10)
            .frame(minWidth: 150)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .disabled(!chat.canSwitchHarness)
        .help(chat.isBusy
              ? "Espere o turno terminar para trocar de harness"
              : "Trocar de harness levando a conversa junto")
    }

}
