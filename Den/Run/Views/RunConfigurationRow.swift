import SwiftUI

struct RunConfigurationRow: View {
    let configuration: RunConfiguration
    let instance: RunInstance?
    let isSelected: Bool
    let start: () -> Void
    let stop: () -> Void

    @State private var hovering = false

    private var state: RunState? { instance?.state }

    private var indicator: RunIndicator { state?.indicator ?? .idle }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Self.color(for: indicator))
                .frame(width: 7, height: 7)
            Text(configuration.name)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer(minLength: 6)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(label(at: context.date))
                    .font(.system(size: 12))
                    .foregroundStyle(indicator == .failed ? Theme.removed : Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            controls
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: 32)
        .hoverFill(hovering, selected: isSelected)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(configuration.command?.command ?? "")
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 2) {
            if instance?.isActive == true {
                iconButton("arrow.clockwise", label: "Reiniciar", action: start)
                    .disabled(state == .stopping)
                iconButton("stop.fill", label: "Parar", action: stop)
                    .disabled(state == .stopping)
            } else {
                iconButton("play.fill", label: "Executar", action: start)
            }
        }
    }

    private func iconButton(_ symbol: String, label: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(symbol == "play.fill" ? Theme.accent : Theme.textSecondary)
                .iconLabel(size: 26)
        }
        .buttonStyle(.denGhost(radius: 7))
        .help(label)
        .accessibilityLabel(label)
    }

    private func label(at now: Date) -> String {
        guard let instance else { return RunState.neverStartedLabel }
        return instance.state.label(startedAt: instance.startedAt, now: now)
    }

    static func color(for indicator: RunIndicator) -> Color {
        switch indicator {
        case .running: Theme.added
        case .busy: Theme.modified
        case .failed: Theme.removed
        case .idle: Theme.textFaint
        }
    }
}
