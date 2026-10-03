import SwiftUI

struct TaskGlyph: View {
    let tone: PullRequestTone?
    var size: CGFloat = 18

    var body: some View {
        Image(systemName: tone?.symbol ?? "arrow.triangle.branch")
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
            .foregroundStyle(tone?.color ?? Theme.textTertiary)
            .frame(width: size - 3, height: size - 3)
            .frame(width: size, height: size)
            .animation(.easeInOut(duration: 0.25), value: tone)
    }
}
