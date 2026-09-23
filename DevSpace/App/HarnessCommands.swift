import SwiftUI
import HarnessCore

extension FocusedValues {
    @Entry var chat: ChatModel?
}

struct HarnessCommands: Commands {
    @FocusedValue(\.chat) private var chat

    var body: some Commands {
        CommandMenu("Harness") {
            ForEach(HarnessRegistry.all.map(\.id), id: \.rawValue) { candidate in
                Button {
                    Task { await chat?.switchHarness(to: candidate) }
                } label: {
                    if chat?.harness == candidate {
                        Label("\(HarnessBadge.name(for: candidate))", systemImage: "checkmark")
                    } else {
                        Text(HarnessBadge.name(for: candidate))
                    }
                }
                .disabled(chat == nil
                          || chat?.harness == candidate
                          || chat?.canSwitchHarness == false)
            }
        }
    }
}
