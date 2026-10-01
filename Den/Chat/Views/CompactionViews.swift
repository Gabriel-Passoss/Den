import SwiftUI

struct CompactionProgressCard: View {
    let since: Date

    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: 30, height: 30)
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Compactando a conversa")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 8)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(Self.elapsed(context.date.timeIntervalSince(since)))
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                track

                Text("Resumindo o histórico para liberar contexto")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: 440, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            phase = 0
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
        .accessibilityLabel("Compactando a conversa")
    }

    private var track: some View {
        GeometryReader { geometry in
            let full = geometry.size.width
            let highlight = max(56, full * 0.36)
            Capsule()
                .fill(Theme.hoverRaised)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Color.accentColor.opacity(0),
                                     Color.accentColor.opacity(0.85),
                                     Color.accentColor.opacity(0)],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: highlight)
                        .offset(x: -highlight + (full + highlight) * phase)
                }
                .clipShape(Capsule())
        }
        .frame(height: 5)
    }

    private static func elapsed(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration))
        return seconds < 60 ? "\(seconds)s" : "\(seconds / 60)min \(seconds % 60)s"
    }
}

struct CompactionMark: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            rule
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 9, weight: .semibold))
                Text(text)
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.raised, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
            rule
        }
        .frame(maxWidth: .infinity)
        .help("A partir daqui a IA só enxerga o resumo do que veio antes")
    }

    private var rule: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
    }
}

struct DigestRow: View {
    let title: String
    let text: String
    let mono: Bool
    let isOpen: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                    Image(systemName: mono ? "terminal" : "text.quote")
                        .font(.system(size: 10))
                    Text(title)
                        .font(.system(size: 12.5, weight: .medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.textMuted)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isOpen ? "Recolher" : "Ver o conteúdo")
            .accessibilityLabel(isOpen ? "Recolher \(title)" : "Expandir \(title)")

            if isOpen {
                body(of: text)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Theme.borderCard, lineWidth: 1))
    }

    @ViewBuilder
    private func body(of text: String) -> some View {
        let shown = String(text.prefix(20_000))
        if mono {
            Text(shown)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            MarkdownText(text: shown)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
