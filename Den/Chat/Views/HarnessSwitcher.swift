import SwiftUI
import HarnessCore

struct HarnessSwitcher: View {
    let chat: ChatModel

    private var sections: [DenMenuSection] {
        [DenMenuSection(header: "Harness desta sessão",
                        items: chat.availableHarnesses.map { candidate in
            DenMenuItem(id: candidate.rawValue,
                        title: HarnessBadge.name(for: candidate),
                        icon: .image(HarnessBadge.menuIcon(for: candidate)),
                        isSelected: candidate == chat.harness,
                        isEnabled: candidate != chat.harness) {
                Task { await chat.switchHarness(to: candidate) }
            }
        })]
    }

    var body: some View {
        DenMenuChip(sections: sections, bordered: true, radius: 10) {
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
