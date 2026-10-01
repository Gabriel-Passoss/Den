import SwiftUI

struct TypingIndicator: View {
    @State private var lit = 0

    private static let step: Double = 0.28

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 6, height: 6)
                    .opacity(lit == index ? 1 : 0.28)
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
        .accessibilityLabel("Pensando")
    }
}

struct ThinkingRow: View {
    let chat: ChatModel

    var body: some View {
        HStack(spacing: 10) {
            TypingIndicator()
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Self.label(for: chat, at: context.date))
                    .font(.system(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    static func label(for chat: ChatModel, at now: Date) -> String {
        let verb = chat.compactingSince == nil ? "Pensando" : "Compactando"
        guard let start = chat.compactingSince ?? chat.turnStartedAt else { return verb }
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return seconds < 60
            ? "\(verb) · \(seconds)s"
            : "\(verb) · \(seconds / 60)m \(seconds % 60)s"
    }
}
