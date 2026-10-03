import HarnessCore
import SwiftUI

struct AssistantTurn<Content: View>: View {
    let harness: HarnessID
    let showsHeader: Bool
    let moment: Date?
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if showsHeader {
                    HarnessBadge(harness: harness, size: 28)
                } else {
                    Color.clear
                }
            }
            .frame(width: 28, height: showsHeader ? 28 : 1)

            VStack(alignment: .leading, spacing: 8) {
                if showsHeader {
                    HStack(spacing: 6) {
                        Text(HarnessBadge.name(for: harness))
                            .fontWeight(.medium)
                        if let moment {
                            Text("·")
                            Text(moment, format: .dateTime.hour().minute())
                                .monospacedDigit()
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(height: 28, alignment: .center)
                    .padding(.bottom, -6)
                }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
