import SwiftUI
import HarnessCore

struct ContextRing: View {
    let chat: ChatModel
    var showsLabel = true

    @State private var showsDetails = false
    @State private var hovering = false

    var body: some View {
        Button { showsDetails.toggle() } label: {
            HStack(spacing: 7) {
                ring
                    .frame(width: 16, height: 16)
                if showsLabel {
                    Text(shortLabel)
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(level == .calm ? Theme.textTertiary : level.color)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(hovering || showsDetails ? Theme.hover : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tooltip)
        .accessibilityLabel("Janela de contexto")
        .accessibilityValue(chat.contextFraction.map(ContextFormat.percent) ?? "sem dados")
        .popover(isPresented: $showsDetails, arrowEdge: .top) {
            ContextPanel(chat: chat)
                .presentationBackground(Theme.raised)
                .environment(\.colorScheme, .dark)
        }
        .onChange(of: showsDetails) { _, shown in
            if shown { Task { await chat.refreshContextUsage() } }
        }
    }

    private var level: ContextLevel { ContextLevel(fraction: chat.contextFraction ?? 0) }

    private var ring: some View {
        let fraction = chat.contextFraction ?? 0
        return ZStack {
            Circle()
                .stroke(Theme.borderControl, lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(fraction, chat.contextTokens > 0 ? 0.02 : 0))
                .stroke(level.color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.easeInOut(duration: 0.4), value: fraction)
    }

    private var shortLabel: String {
        chat.contextFraction.map(ContextFormat.percent) ?? ContextFormat.tokens(chat.contextTokens)
    }

    private var tooltip: String {
        guard let window = chat.contextWindow else {
            return "\(ContextFormat.tokens(chat.contextTokens)) tokens no contexto"
        }
        return "Contexto: \(ContextFormat.summary(used: chat.contextTokens, window: window))"
            + " · clique para ver o que ocupa a janela"
    }
}

extension ContextLevel {
    var color: Color {
        switch self {
        case .calm: Color(hex: 0x93AEE8)
        case .warning: Color(hex: 0xE0B45F)
        case .critical: Color(hex: 0xF08C7E)
        }
    }
}
