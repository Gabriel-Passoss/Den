import SwiftUI

struct StatusIndicator: View {
    let status: TaskStatus
    let isAnimated: Bool

    var body: some View {
        HStack(spacing: Theme.space4) {
            ZStack {
                Image(systemName: status.symbol)
                    .font(.system(size: Theme.font11, weight: .semibold))
                if isAnimated {
                    ActivityPulse(color: status.color)
                }
            }
            .frame(width: Theme.space16, height: Theme.space16)
            Text(status.label)
                .font(.system(size: Theme.font12, weight: .medium))
        }
        .foregroundStyle(status.color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.label)
    }
}

private struct ActivityPulse: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.3)
            .stroke(color, style: StrokeStyle(lineWidth: Theme.emphasisStroke, lineCap: .round))
            .rotationEffect(.degrees(turning ? 360 : 0))
            .animation(reduceMotion ? nil : .linear(duration: 1.2).repeatForever(autoreverses: false),
                       value: turning)
            .onAppear { turning = !reduceMotion }
            .onChange(of: reduceMotion) { _, reduced in turning = !reduced }
    }
}

#Preview("Falhou") { StatusIndicator(status: .failed, isAnimated: false).padding() }

#Preview("Precisa de você") { StatusIndicator(status: .needsMe, isAnimated: false).padding() }

#Preview("Em execução") { StatusIndicator(status: .running, isAnimated: true).padding() }

#Preview("Concluído") { StatusIndicator(status: .concluded, isAnimated: false).padding() }

#Preview("Parada") { StatusIndicator(status: .stopped, isAnimated: false).padding() }

#Preview("Não iniciada") { StatusIndicator(status: .notStarted, isAnimated: false).padding() }
