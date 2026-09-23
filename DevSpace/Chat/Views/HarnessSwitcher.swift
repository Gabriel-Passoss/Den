import SwiftUI
import HarnessCore

struct HarnessSwitcher: View {
    let cockpit: CockpitModel

    var body: some View {
        Menu {
            ForEach(HarnessRegistry.all.map(\.id), id: \.rawValue) { candidate in
                Button {
                    Task { await cockpit.switchHarness(to: candidate) }
                } label: {
                    Label {
                        Text(HarnessBadge.name(for: candidate))
                    } icon: {
                        HarnessBadge(harness: candidate, size: 14)
                    }
                }
                .disabled(candidate == cockpit.harness)
            }
        } label: {
            HStack(spacing: 6) {
                HarnessBadge(harness: cockpit.harness, size: 15)
                Text(cockpit.harnessName)
            }
            .padding(.horizontal, 6)
        }
        .labelStyle(.titleAndIcon)
        .disabled(!cockpit.canSwitchHarness)
        .help(cockpit.isBusy
              ? "Espere o turno terminar para trocar de harness"
              : "Trocar de harness levando a conversa junto")
    }

}
