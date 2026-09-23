import SwiftUI
import HarnessCore

extension FocusedValues {
    @Entry var cockpit: CockpitModel?
}

/// `toolbars.md › Desktop (macOS)`: "Make every toolbar item available as a
/// command in the menu bar. Because people can customize the toolbar or hide
/// it, it can't be the only place that presents a command."
struct HarnessCommands: Commands {
    @FocusedValue(\.cockpit) private var cockpit

    var body: some Commands {
        CommandMenu("Harness") {
            ForEach(HarnessRegistry.all.map(\.id), id: \.rawValue) { candidate in
                Button {
                    Task { await cockpit?.switchHarness(to: candidate) }
                } label: {
                    if cockpit?.harness == candidate {
                        Label("\(HarnessBadge.name(for: candidate))", systemImage: "checkmark")
                    } else {
                        Text(HarnessBadge.name(for: candidate))
                    }
                }
                .disabled(cockpit == nil
                          || cockpit?.harness == candidate
                          || cockpit?.canSwitchHarness == false)
            }
        }
    }
}
