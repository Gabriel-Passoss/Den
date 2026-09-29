import SwiftUI

struct RunConfigurationRow: View {
    let configuration: RunConfiguration
    let instance: RunInstance?
    let isSelected: Bool
    let start: () -> Void
    let stop: () -> Void

    private var state: RunState? { instance?.state }

    private var indicator: RunIndicator { state?.indicator ?? .idle }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
            Text(configuration.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 6)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(label(at: context.date))
                    .font(.system(size: 11))
                    .foregroundStyle(indicator == .failed
                                     ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            controls
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(isSelected ? AnyShapeStyle(.quaternary.opacity(0.7)) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
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
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(label)
        .accessibilityLabel(label)
    }

    private func label(at now: Date) -> String {
        guard let instance else { return RunState.neverStartedLabel }
        return instance.state.label(startedAt: instance.startedAt, now: now)
    }

    private var dotColor: Color {
        switch indicator {
        case .running: .green
        case .busy: .yellow
        case .failed: .red
        case .idle: .gray.opacity(0.5)
        }
    }
}
