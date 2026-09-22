import SwiftUI

struct TypingIndicator: View {
    @State private var lit = 0

    private static let step: Double = 0.28

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.secondary)
                    .frame(width: 6, height: 6)
                    .opacity(lit == index ? 1 : 0.25)
                    .scaleEffect(lit == index ? 1.15 : 1)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.step))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: Self.step)) {
                    lit = (lit + 1) % 3
                }
            }
        }
        .accessibilityLabel("Claude está escrevendo")
    }
}
