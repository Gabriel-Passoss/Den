import SwiftUI

struct NeedsMeCounter: View {
    let count: Int

    var body: some View {
        if let label = BoardPresentation.needsMeLabel(count) {
            HStack(spacing: Theme.space4) {
                Image(systemName: TaskStatus.needsMe.symbol)
                    .font(.system(size: Theme.font11, weight: .semibold))
                Text(label)
                    .font(.system(size: Theme.font12, weight: .medium))
            }
            .foregroundStyle(TaskStatus.needsMe.color)
            .padding(.horizontal, Theme.space8)
            .padding(.vertical, Theme.space4)
            .background(Theme.raised, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
        }
    }
}

#Preview("1") { NeedsMeCounter(count: 1).padding() }

#Preview("Várias") { NeedsMeCounter(count: 3).padding() }

#Preview("Zero") { NeedsMeCounter(count: 0).padding() }
