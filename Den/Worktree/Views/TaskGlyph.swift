import SwiftUI
import HarnessCore

struct TaskGlyph: View {
    let tone: PullRequestTone?
    let harness: HarnessID?

    var body: some View {
        Image(systemName: tone?.symbol ?? "arrow.triangle.branch")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tone.map { AnyShapeStyle($0.color) } ?? AnyShapeStyle(.secondary))
            .frame(width: 18, height: 18)
            .animation(.easeInOut(duration: 0.25), value: tone)
            .overlay(alignment: .bottomTrailing) {
                HarnessBadge(harness: harness, size: 9)
                    .padding(1.5)
                    .background(Color(nsColor: .windowBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .offset(x: 4, y: 4)
            }
    }
}
